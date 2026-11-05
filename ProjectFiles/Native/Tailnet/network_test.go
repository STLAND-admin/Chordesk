package main

import (
	"context"
	"encoding/json"
	"net/netip"
	"strings"
	"testing"
	"time"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/types/key"
)

func TestHomeDERPIsNeverEvidenceOfRelayedPeerTraffic(t *testing.T) {
	d := newPathDiagnostics(nil)
	defer d.close()
	status := &ipnstate.Status{Self: &ipnstate.PeerStatus{Relay: "hkg"}, Peer: map[key.NodePublic]*ipnstate.PeerStatus{
		{}: {Relay: "hkg", Active: false, TailscaleIPs: []netip.Addr{netip.MustParseAddr("100.64.1.2")}},
	}}
	r := d.snapshot(status)
	if r.HomeDERP != "hkg" || len(r.Paths) != 0 {
		t.Fatal("home relay falsely described as active session path")
	}
	peer := status.Peer[key.NodePublic{}]
	peer.Active = true
	peer.CurAddr = "[2001:db8::1]:40000"
	r = d.snapshot(status)
	if len(r.Paths) != 1 || r.Paths[0].Kind != "direct" || r.Paths[0].Region != "" {
		t.Fatal(r)
	}
	data, _ := json.Marshal(r)
	if strings.Contains(string(data), "2001:db8") {
		t.Fatal("public endpoint leaked into UI diagnostics")
	}
}
func TestMeasuredPathsDistinguishDirectDERPAndPeerRelay(t *testing.T) {
	for _, test := range []struct {
		result ipnstate.PingResult
		kind   string
	}{
		{ipnstate.PingResult{Endpoint: "198.51.100.3:4", DERPRegionID: 20}, "direct"},
		{ipnstate.PingResult{DERPRegionID: 20, DERPRegionCode: "hkg"}, "derp"},
		{ipnstate.PingResult{PeerRelay: "198.51.100.1:4:vni:1"}, "peer-relay"},
		{ipnstate.PingResult{}, "unknown"},
	} {
		if got := measuredPath("100.64.1.2", &test.result, time.Now()); got.Kind != test.kind {
			t.Fatal(got)
		}
	}
}
func TestSnapshotUsesMatchingIPv6ProbeAndExpiresOldSamples(t *testing.T) {
	d := newPathDiagnostics(nil)
	defer d.close()
	ip4, ip6 := netip.MustParseAddr("100.64.1.2"), netip.MustParseAddr("fd7a:115c:a1e0::2")
	status := &ipnstate.Status{Peer: map[key.NodePublic]*ipnstate.PeerStatus{{}: {Active: true, Relay: "hkg", TailscaleIPs: []netip.Addr{ip4, ip6}}}}
	d.paths[ip6.String()] = peerPath{Address: ip6.String(), Kind: "direct", CheckedAt: time.Now().Unix()}
	if got := d.snapshot(status).Paths; len(got) != 1 || got[0].Kind != "direct" {
		t.Fatal(got)
	}
	d.paths[ip6.String()] = peerPath{Address: ip6.String(), Kind: "direct", CheckedAt: time.Now().Add(-time.Minute).Unix()}
	if got := d.snapshot(status).Paths; len(got) != 1 || got[0].Kind != "derp" {
		t.Fatal("stale probe masked current route", got)
	}
}
func TestInvalidOrStoppedPrewarmNeverStartsNetworkWork(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	d := &pathDiagnostics{ctx: ctx, paths: map[string]peerPath{}, lastProbe: map[string]time.Time{}}
	for _, host := range []string{"8.8.8.8", "example.com", "100.64.1.2", "fd7a:115c:a1e0::2"} {
		d.prewarm(host)
	}
	if len(d.lastProbe) != 0 {
		t.Fatal("stopped engine accepted a discovery task")
	}
}
