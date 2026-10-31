package main

import (
	"bytes"
	"context"
	"io"
	"net"
	"strings"
	"testing"
	"time"
)

func TestHealthDiagnosticsNeverExposeLoginURLTokens(t *testing.T) {
	value := safeHealth([]string{"Visit https://login.tailscale.com/a/SECRET_TOKEN to sign in", "offline", "third", "fourth"})
	if len(value) != 3 || strings.Contains(strings.Join(value, " "), "SECRET_TOKEN") {
		t.Fatal("unsafe health diagnostics")
	}
	if !strings.Contains(value[0], "[service link]") {
		t.Fatal("diagnostic redaction missing")
	}
}

func TestTailnetEndpointIsStrictIPv4(t *testing.T) {
	for _, v := range []string{"100.64.0.1", "100.127.255.254"} {
		if !tailnetIPv4(v) {
			t.Fatal(v)
		}
	}
	for _, v := range []string{"8.8.8.8", "192.168.1.1", "100.128.0.1", "100.063.1.1", "::ffff:100.64.1.1", "host.ts.net", "100.64.0.1:80"} {
		if tailnetIPv4(v) {
			t.Fatal(v)
		}
	}
}
func TestBridgePreservesBytesAndCloseTearsDownBothDirections(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	far := make(chan net.Conn, 1)
	b := serveBridge(ln, true, func(context.Context) (net.Conn, error) { a, z := net.Pipe(); far <- z; return a, nil })
	defer b.close()
	c, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	peer := <-far
	defer peer.Close()
	c.SetDeadline(time.Now().Add(3 * time.Second))
	peer.SetDeadline(time.Now().Add(3 * time.Second))
	expected := bytes.Repeat([]byte{0, 255, 1, 17}, 100000)
	done := make(chan error, 1)
	go func() { _, err := c.Write(expected); done <- err }()
	got := make([]byte, len(expected))
	if _, err := io.ReadFull(peer, got); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, expected) {
		t.Fatal("bridge changed payload")
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	go func() { _, err := peer.Write([]byte("reply")); done <- err }()
	got = make([]byte, 5)
	if _, err := io.ReadFull(c, got); err != nil {
		t.Fatal(err)
	}
	if string(got) != "reply" {
		t.Fatal("bad reply")
	}
	<-done
	b.close()
	if _, err := c.Read(make([]byte, 1)); err == nil {
		t.Fatal("client did not close")
	}
	if _, err := peer.Read(make([]byte, 1)); err == nil {
		t.Fatal("peer did not close")
	}
	if extra, err := net.DialTimeout("tcp", ln.Addr().String(), time.Second); err == nil {
		extra.Close()
		t.Fatal("single-use port remained open")
	}
}
func TestClosedBridgeRejectsNewConnection(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	b := serveBridge(ln, false, func(context.Context) (net.Conn, error) { return nil, io.EOF })
	b.close()
	a, z := net.Pipe()
	defer z.Close()
	if b.track(a) {
		t.Fatal("closed bridge accepted a connection")
	}
}
