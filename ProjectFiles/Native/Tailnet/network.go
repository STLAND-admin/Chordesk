package main

import (
	"context"
	"net"
	"net/netip"
	"sort"
	"sync"
	"time"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/net/netcheck"
	"tailscale.com/net/netmon"
	"tailscale.com/tailcfg"
	"tailscale.com/tsnet"
	"tailscale.com/types/logger"
	"tailscale.com/util/eventbus"
)

type relayRegion struct {
	Code string `json:"code"`
	Name string `json:"name"`
}
type peerPath struct {
	Address   string  `json:"address"` // overlay IP only; no public endpoints or node keys
	Kind      string  `json:"kind"`
	Region    string  `json:"region,omitempty"`
	LatencyMS float64 `json:"latencyMS,omitempty"`
	CheckedAt int64   `json:"checkedAt,omitempty"`
}
type connectivityReport struct {
	UDP       bool         `json:"udp"`
	IPv4      bool         `json:"ipv4"`
	IPv6      bool         `json:"ipv6"`
	NATVaries string       `json:"natVaries,omitempty"`
	Nearest   *relayRegion `json:"nearest,omitempty"`
	CheckedAt int64        `json:"checkedAt"`
}
type networkSnapshot struct {
	HomeDERP string              `json:"homeDERP,omitempty"`
	Regions  []relayRegion       `json:"regions,omitempty"`
	Paths    []peerPath          `json:"paths,omitempty"`
	Checking bool                `json:"checking"`
	Probe    *connectivityReport `json:"probe,omitempty"`
	Error    string              `json:"error,omitempty"`
}
type pathDiagnostics struct {
	server     *tsnet.Server
	ctx        context.Context
	cancel     context.CancelFunc
	mu         sync.Mutex
	regions    []relayRegion
	paths      map[string]peerPath
	lastProbe  map[string]time.Time
	checking   bool
	probe      *connectivityReport
	probeError string
}

func newPathDiagnostics(server *tsnet.Server) *pathDiagnostics {
	ctx, cancel := context.WithCancel(context.Background())
	return &pathDiagnostics{server: server, ctx: ctx, cancel: cancel, paths: map[string]peerPath{}, lastProbe: map[string]time.Time{}}
}
func (d *pathDiagnostics) close() { d.cancel() }

func observedPath(p *ipnstate.PeerStatus) string {
	if p == nil || !p.Active {
		return "unknown"
	}
	if p.CurAddr != "" {
		return "direct"
	}
	if p.PeerRelay != "" {
		return "peer-relay"
	}
	if p.Relay != "" {
		return "derp"
	}
	return "unknown"
}
func (d *pathDiagnostics) snapshot(status *ipnstate.Status) networkSnapshot {
	d.mu.Lock()
	defer d.mu.Unlock()
	r := networkSnapshot{Regions: append([]relayRegion(nil), d.regions...), Checking: d.checking, Probe: d.probe, Error: d.probeError}
	if status.Self != nil {
		r.HomeDERP = status.Self.Relay
	}
	for _, p := range status.Peer {
		if p == nil || !p.Active {
			continue
		}
		var chosen *peerPath
		for _, ip := range p.TailscaleIPs {
			if !tailnetAddress(ip.String()) {
				continue
			}
			path := peerPath{Address: ip.String(), Kind: observedPath(p)}
			if path.Kind == "derp" {
				path.Region = p.Relay
			}
			// Ping results are measured samples, not everlasting route guarantees.
			if cached, ok := d.paths[path.Address]; ok && time.Since(time.Unix(cached.CheckedAt, 0)) < 15*time.Second {
				chosen = &cached
				break
			}
			if chosen == nil {
				chosen = &path
			}
		}
		if chosen != nil {
			r.Paths = append(r.Paths, *chosen)
		}
	}
	sort.Slice(r.Paths, func(i, j int) bool { return r.Paths[i].Address < r.Paths[j].Address })
	if len(r.Paths) > 3 {
		r.Paths = r.Paths[:3]
	}
	return r
}

// Bounded discovery uses the live embedded node, not an external Tailscale app.
// It runs beside Dial, never before it, and cannot probe arbitrary Internet IPs.
func (d *pathDiagnostics) prewarm(address string) {
	if !tailnetAddress(address) {
		return
	}
	d.mu.Lock()
	if d.ctx.Err() != nil || time.Since(d.lastProbe[address]) < 10*time.Second {
		d.mu.Unlock()
		return
	}
	d.lastProbe[address] = time.Now()
	// Keep reconnect/probe bookkeeping bounded without exporting peer identities.
	if len(d.lastProbe) > 24 {
		oldest := ""
		for key, when := range d.lastProbe {
			if key != address && (oldest == "" || when.Before(d.lastProbe[oldest])) {
				oldest = key
			}
		}
		delete(d.lastProbe, oldest)
		delete(d.paths, oldest)
	}
	d.mu.Unlock()
	go func() {
		ctx, cancel := context.WithTimeout(d.ctx, 5*time.Second)
		defer cancel()
		lc, err := d.server.LocalClient()
		if err != nil {
			return
		}
		for i := 0; i < 4 && ctx.Err() == nil; i++ {
			attempt, finish := context.WithTimeout(ctx, time.Second)
			p, err := lc.Ping(attempt, netip.MustParseAddr(address), tailcfg.PingDisco)
			finish()
			if err == nil && p != nil && p.Err == "" {
				path := measuredPath(address, p, time.Now())
				d.mu.Lock()
				d.paths[address] = path
				d.mu.Unlock()
				if path.Kind == "direct" {
					return
				}
			}
			select {
			case <-ctx.Done():
				return
			case <-time.After(300 * time.Millisecond):
			}
		}
	}()
}
func measuredPath(address string, p *ipnstate.PingResult, now time.Time) peerPath {
	r := peerPath{Address: address, Kind: "unknown", LatencyMS: p.LatencySeconds * 1000, CheckedAt: now.Unix()}
	switch {
	case p.Endpoint != "":
		r.Kind = "direct"
	case p.PeerRelay != "":
		r.Kind = "peer-relay"
	case p.DERPRegionID != 0:
		r.Kind = "derp"
		r.Region = p.DERPRegionCode
	}
	return r
}

// User-requested STUN/DERP checks use a separate temporary socket. This report
// describes network reachability, not proof that a particular session is direct.
func (d *pathDiagnostics) inspect() {
	d.mu.Lock()
	if d.checking || d.ctx.Err() != nil {
		d.mu.Unlock()
		return
	}
	d.checking = true
	d.probeError = ""
	d.mu.Unlock()
	go func() {
		ctx, cancel := context.WithTimeout(d.ctx, 8*time.Second)
		defer cancel()
		defer func() { d.mu.Lock(); d.checking = false; d.mu.Unlock() }()
		fail := func() {
			d.mu.Lock()
			d.probeError = "网络探测未完成，请稍后重试；不代表设备已退出登录"
			d.mu.Unlock()
		}
		lc, err := d.server.LocalClient()
		if err != nil {
			fail()
			return
		}
		dm, err := lc.CurrentDERPMap(ctx)
		if err != nil || dm == nil {
			fail()
			return
		}
		regions := []relayRegion{}
		for _, region := range dm.Regions {
			regions = append(regions, relayRegion{Code: region.RegionCode, Name: region.RegionName})
		}
		sort.Slice(regions, func(i, j int) bool { return regions[i].Code < regions[j].Code })
		d.mu.Lock()
		d.regions = regions
		d.mu.Unlock()
		if status, err := lc.Status(ctx); err == nil {
			count := 0
			for _, peer := range status.Peer {
				if !peer.Active || len(peer.TailscaleIPs) == 0 || count == 2 {
					continue
				}
				d.prewarm(peer.TailscaleIPs[0].String())
				count++
			}
		}
		bus := eventbus.New()
		defer bus.Close()
		monitor, err := netmon.New(bus, logger.Discard)
		if err != nil {
			fail()
			return
		}
		defer monitor.Close()
		client := &netcheck.Client{NetMon: monitor, Logf: logger.Discard, UseDNSCache: false}
		if err := client.Standalone(ctx, ":0"); err != nil {
			fail()
			return
		}
		report, err := client.GetReport(ctx, dm, nil)
		if err != nil {
			fail()
			return
		}
		probe := &connectivityReport{UDP: report.UDP, IPv4: report.IPv4, IPv6: report.IPv6, NATVaries: string(report.MappingVariesByDestIP), CheckedAt: time.Now().Unix()}
		if nearest := dm.Regions[report.PreferredDERP]; nearest != nil {
			probe.Nearest = &relayRegion{Code: nearest.RegionCode, Name: nearest.RegionName}
		}
		d.mu.Lock()
		d.probe = probe
		d.mu.Unlock()
	}()
}

type observedListener struct {
	net.Listener
	accepted func(net.Conn)
}

func (l *observedListener) Accept() (net.Conn, error) {
	c, err := l.Listener.Accept()
	if err == nil {
		l.accepted(c)
	}
	return c, err
}
