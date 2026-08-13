// Command kcal is a small self-hosted calorie and macro tracker.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/hunternuga/homelab/services/kcal/app/internal/auth"
	"github.com/hunternuga/homelab/services/kcal/app/internal/store"
	"github.com/hunternuga/homelab/services/kcal/app/internal/web"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	if err := run(log); err != nil {
		log.Error("kcal exited", "error", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	port := getenv("PORT", "8080")
	dbPath := getenv("DB_PATH", "/data/kcal.db")
	sessionSecret := os.Getenv("SESSION_SECRET")
	if sessionSecret == "" {
		return errors.New("SESSION_SECRET must be set")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	st, err := store.Open(ctx, dbPath)
	if err != nil {
		return err
	}
	defer st.Close()

	srv, err := web.NewServer(st, auth.NewManager(sessionSecret), log)
	if err != nil {
		return err
	}

	httpServer := &http.Server{
		Addr:              ":" + port,
		Handler:           srv.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("kcal listening", "port", port, "db_path", dbPath)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		log.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return httpServer.Shutdown(shutdownCtx)
	}
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
