// Package web implements kcal's HTTP handlers, templates, and routing.
package web

import (
	"context"
	"html/template"
	"log/slog"
	"net/http"

	"github.com/hunternuga/homelab/services/kcal/app/internal/auth"
	"github.com/hunternuga/homelab/services/kcal/app/internal/store"
)

type Server struct {
	store *store.Store
	auth  *auth.Manager
	tmpl  map[string]*template.Template
	log   *slog.Logger
}

func NewServer(st *store.Store, authMgr *auth.Manager, log *slog.Logger) (*Server, error) {
	tmpl, err := loadTemplates()
	if err != nil {
		return nil, err
	}
	return &Server{store: st, auth: authMgr, tmpl: tmpl, log: log}, nil
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()

	mux.Handle("GET /static/", http.StripPrefix("/static/", http.FileServerFS(staticFS())))

	mux.HandleFunc("GET /register", s.handleRegisterForm)
	mux.HandleFunc("POST /register", s.handleRegister)
	mux.HandleFunc("GET /login", s.handleLoginForm)
	mux.HandleFunc("POST /login", s.handleLogin)
	mux.HandleFunc("POST /logout", s.handleLogout)

	mux.HandleFunc("GET /{$}", s.requireAuth(s.handleDashboard))
	mux.HandleFunc("POST /entries", s.requireAuth(s.handleAddEntry))
	mux.HandleFunc("POST /entries/{id}/delete", s.requireAuth(s.handleDeleteEntry))
	mux.HandleFunc("GET /history", s.requireAuth(s.handleHistory))

	return mux
}

type ctxKey int

const userCtxKey ctxKey = 0

func userFromContext(ctx context.Context) *store.User {
	u, _ := ctx.Value(userCtxKey).(*store.User)
	return u
}

// requireAuth resolves the session cookie into a *store.User and stores it
// in the request context, redirecting to /login when there is none.
func (s *Server) requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, err := s.currentUser(r)
		if err != nil {
			http.Redirect(w, r, "/login", http.StatusSeeOther)
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), userCtxKey, user)))
	}
}

func (s *Server) currentUser(r *http.Request) (*store.User, error) {
	c, err := r.Cookie(auth.CookieName)
	if err != nil {
		return nil, auth.ErrInvalidSession
	}
	userID, err := s.auth.UserID(c.Value)
	if err != nil {
		return nil, err
	}
	return s.store.GetUser(r.Context(), userID)
}

func (s *Server) render(w http.ResponseWriter, status int, page string, data any) {
	t, ok := s.tmpl[page]
	if !ok {
		s.log.Error("unknown template", "page", page)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	if err := t.ExecuteTemplate(w, "layout", data); err != nil {
		s.log.Error("render template", "page", page, "error", err)
	}
}
