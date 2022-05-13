//go:build v0.11
// +build v0.11

package compat

import (
	"context"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p-core/host"
	"github.com/libp2p/go-libp2p/config"
)

func NewLibp2(ctx context.Context, opts ...config.Option) (host.Host, error) {
	return libp2p.New(
		ctx,
		opts...,
	)
}
