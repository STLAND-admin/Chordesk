package main

/*
#cgo LDFLAGS: -framework Security -framework CoreFoundation -framework SystemConfiguration -lresolv
#include <stdlib.h>
#include "keychain.h"
*/
import "C"

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"regexp"
	"strconv"
	"sync"
	"time"
	"unsafe"

	"tailscale.com/envknob"
	"tailscale.com/ipn"
	"tailscale.com/tsnet"
)

// No Tailscale private keys are persisted to ordinary files. Keychain errors
// fail closed instead of silently registering a new device or falling back.
type secureStore struct {
	mu     sync.Mutex
	values map[ipn.StateKey][]byte
}

func loadStore() (*secureStore, error) {
	var data unsafe.Pointer
	var length C.size_t
	code := C.cr_state_read(&data, &length)
	if code != 0 {
		return nil, fmt.Errorf("Keychain read failed (%d)", code)
	}
	if data != nil {
		defer C.free(data)
	}
	s := &secureStore{values: map[ipn.StateKey][]byte{}}
	if length > 0 {
		if err := json.Unmarshal(C.GoBytes(data, C.int(length)), &s.values); err != nil {
			return nil, errors.New("invalid Keychain node state")
		}
	}
	return s, nil
}
func (s *secureStore) ReadState(key ipn.StateKey) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	b, ok := s.values[key]
	if !ok {
		return nil, ipn.ErrStateNotExist
	}
	return append([]byte(nil), b...), nil
}
func (s *secureStore) WriteState(key ipn.StateKey, value []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	next := make(map[ipn.StateKey][]byte, len(s.values)+1)
	for k, v := range s.values {
		next[k] = v
	}
	if value == nil {
		delete(next, key)
	} else {
		next[key] = append([]byte(nil), value...)
	}
	b, err := json.Marshal(next)
	if err != nil {
		return err
	}
	ptr := C.CBytes(b)
	defer C.free(ptr)
	if code := C.cr_state_write(ptr, C.size_t(len(b))); code != 0 {
		return fmt.Errorf("Keychain write failed (%d)", code)
	}
	s.values = next
	return nil
}

type engine struct {
	server      *tsnet.Server
	forward     *byteBridge
	forwardPort int
	dials       map[int]*byteBridge
}

var apiMu sync.Mutex
var active *engine
var nextDial int
var diagnosticURL = regexp.MustCompile(`https?://[^\s<>]+`)

func safeHealth(values []string) []string {
	result := []string{}
	for _, text := range values {
		// Health notices can include a login link. Keep actionable state,
		// never expose a one-time authorization token in diagnostics.
		text = diagnosticURL.ReplaceAllString(text, "[service link]")
		if len(text) > 400 {
			text = text[:400]
		}
		result = append(result, text)
		if len(result) == 3 {
			break
		}
	}
	return result
}
func result(value any) *C.char  { b, _ := json.Marshal(value); return C.CString(string(b)) }
func failure(err error) *C.char { return result(map[string]any{"error": err.Error()}) }
func success() *C.char          { return result(map[string]any{"ok": true}) }
func requireEngine() error {
	if active == nil {
		return errors.New("公网节点未启动，请先登录 Tailscale")
	}
	return nil
}
func snapshot() *C.char {
	if active == nil {
		return result(map[string]any{"state": "Stopped"})
	}
	lc, err := active.server.LocalClient()
	if err != nil {
		return failure(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	status, err := lc.StatusWithoutPeers(ctx)
	if err != nil {
		return failure(err)
	}
	addresses := []string{}
	for _, ip := range status.TailscaleIPs {
		if tailnetIPv4(ip.String()) {
			addresses = append(addresses, ip.String())
		}
	}
	return result(map[string]any{"state": status.BackendState, "authURL": status.AuthURL, "addresses": addresses, "health": safeHealth(status.Health)})
}

//export CRStart
func CRStart(directory, hostname *C.char) *C.char {
	apiMu.Lock()
	defer apiMu.Unlock()
	if active != nil {
		return snapshot()
	}
	store, err := loadStore()
	if err != nil {
		return failure(err)
	}
	dir := C.GoString(directory)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return failure(err)
	}
	// Chordesk only supports interactive, per-user accounts. Never pick up a
	// developer shell's auth key or alternate control plane by accident.
	for _, key := range []string{"TS_AUTHKEY", "TS_AUTH_KEY", "TS_CLIENT_SECRET", "TS_CLIENT_ID", "TS_ID_TOKEN", "TS_AUDIENCE", "TSNET_FORCE_LOGIN"} {
		os.Unsetenv(key)
	}
	envknob.SetNoLogsNoSupport()
	discard := func(string, ...any) {}
	server := &tsnet.Server{Dir: dir, Store: store, Hostname: C.GoString(hostname),
		ControlURL: "https://controlplane.tailscale.com", Logf: discard, UserLogf: discard}
	if err := server.Start(); err != nil {
		server.Close()
		return failure(err)
	}
	active = &engine{server: server, dials: map[int]*byteBridge{}}
	return snapshot()
}

//export CRStatus
func CRStatus() *C.char { apiMu.Lock(); defer apiMu.Unlock(); return snapshot() }

//export CRLogin
func CRLogin() *C.char {
	apiMu.Lock()
	defer apiMu.Unlock()
	if err := requireEngine(); err != nil {
		return failure(err)
	}
	lc, err := active.server.LocalClient()
	if err != nil {
		return failure(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := lc.StartLoginInteractive(ctx); err != nil {
		return failure(err)
	}
	return snapshot()
}
func stop() {
	if active == nil {
		return
	}
	if active.forward != nil {
		active.forward.close()
	}
	for _, b := range active.dials {
		b.close()
	}
	active.server.Close()
	active = nil
}

//export CRStop
func CRStop() *C.char { apiMu.Lock(); defer apiMu.Unlock(); stop(); return success() }

//export CRLogout
func CRLogout() *C.char {
	apiMu.Lock()
	defer apiMu.Unlock()
	if err := requireEngine(); err != nil {
		return failure(err)
	}
	if active.forward != nil {
		active.forward.close()
		active.forward = nil
	}
	for id, b := range active.dials {
		b.close()
		delete(active.dials, id)
	}
	lc, err := active.server.LocalClient()
	if err != nil {
		return failure(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := lc.Logout(ctx); err != nil {
		return failure(err)
	}
	stop()
	return success()
}

// The bridge only copies bytes; Chordesk's existing TLS-PSK handshake and
// framing remain end-to-end between NWConnections on iPhone and Mac.
type byteBridge struct {
	listener net.Listener
	cancel   context.CancelFunc
	mu       sync.Mutex
	closed   bool
	conns    map[net.Conn]bool
}

func (b *byteBridge) close() {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.closed {
		return
	}
	b.closed = true
	b.cancel()
	b.listener.Close()
	for c := range b.conns {
		c.Close()
	}
}
func (b *byteBridge) track(c net.Conn) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.closed {
		c.Close()
		return false
	}
	b.conns[c] = true
	return true
}
func (b *byteBridge) untrack(c net.Conn) { b.mu.Lock(); delete(b.conns, c); b.mu.Unlock(); c.Close() }
func serveBridge(ln net.Listener, once bool, dial func(context.Context) (net.Conn, error)) *byteBridge {
	ctx, cancel := context.WithCancel(context.Background())
	b := &byteBridge{listener: ln, cancel: cancel, conns: map[net.Conn]bool{}}
	slots := make(chan struct{}, 3)
	go func() {
		for {
			in, err := ln.Accept()
			if err != nil {
				return
			}
			select {
			case slots <- struct{}{}:
			default:
				in.Close()
				continue
			}
			if !b.track(in) {
				<-slots
				return
			}
			go func() {
				defer func() { b.untrack(in); <-slots }()
				dialCtx, finish := context.WithTimeout(ctx, 12*time.Second)
				out, err := dial(dialCtx)
				finish()
				if err != nil {
					return
				}
				if !b.track(out) {
					return
				}
				defer b.untrack(out)
				done := make(chan struct{})
				go func() { io.Copy(out, in); out.Close(); close(done) }()
				io.Copy(in, out)
				in.Close()
				<-done
			}()
			if once {
				ln.Close()
				return
			}
		}
	}()
	return b
}
func tailnetIPv4(value string) bool {
	ip, err := netip.ParseAddr(value)
	return err == nil && ip.Is4() && ip.String() == value && netip.MustParsePrefix("100.64.0.0/10").Contains(ip)
}

//export CRForward
func CRForward(localhostPort C.int) *C.char {
	apiMu.Lock()
	defer apiMu.Unlock()
	if err := requireEngine(); err != nil {
		return failure(err)
	}
	p := int(localhostPort)
	if p < 1 || p > 65535 {
		return failure(errors.New("invalid local port"))
	}
	if active.forward != nil && active.forwardPort == p {
		return success()
	}
	if active.forward != nil {
		active.forward.close()
		active.forward = nil
	}
	ln, err := active.server.Listen("tcp", ":49173")
	if err != nil {
		return failure(err)
	}
	active.forward = serveBridge(ln, false, func(ctx context.Context) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(p)))
	})
	active.forwardPort = p
	return success()
}

//export CRStopForward
func CRStopForward() *C.char {
	apiMu.Lock()
	defer apiMu.Unlock()
	if active != nil && active.forward != nil {
		active.forward.close()
		active.forward = nil
	}
	return success()
}

//export CRDial
func CRDial(host *C.char, port C.int) *C.char {
	apiMu.Lock()
	defer apiMu.Unlock()
	if err := requireEngine(); err != nil {
		return failure(err)
	}
	address := C.GoString(host)
	p := int(port)
	if !tailnetIPv4(address) || p < 1 || p > 65535 {
		return failure(errors.New("invalid tailnet endpoint"))
	}
	if len(active.dials) >= 2 {
		return failure(errors.New("too many pending connections"))
	}
	ln, err := net.ListenTCP("tcp4", &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		return failure(err)
	}
	ln.SetDeadline(time.Now().Add(15 * time.Second))
	server := active.server
	b := serveBridge(ln, true, func(ctx context.Context) (net.Conn, error) {
		return server.Dial(ctx, "tcp", net.JoinHostPort(address, strconv.Itoa(p)))
	})
	nextDial++
	active.dials[nextDial] = b
	return result(map[string]any{"port": ln.Addr().(*net.TCPAddr).Port, "identifier": nextDial})
}

//export CRCloseDial
func CRCloseDial(identifier C.int) *C.char {
	apiMu.Lock()
	defer apiMu.Unlock()
	if active != nil {
		if b := active.dials[int(identifier)]; b != nil {
			b.close()
			delete(active.dials, int(identifier))
		}
	}
	return success()
}
func main() {}
