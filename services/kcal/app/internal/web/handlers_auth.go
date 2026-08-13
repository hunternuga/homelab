package web

import (
	"errors"
	"net/http"
	"strings"

	"github.com/hunternuga/homelab/services/kcal/app/internal/auth"
	"github.com/hunternuga/homelab/services/kcal/app/internal/store"
)

func (s *Server) handleRegisterForm(w http.ResponseWriter, r *http.Request) {
	if _, err := s.currentUser(r); err == nil {
		http.Redirect(w, r, "/", http.StatusSeeOther)
		return
	}
	s.render(w, http.StatusOK, "register.html", authFormData{Base: Base{Title: "Register"}})
}

func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	username := strings.TrimSpace(r.FormValue("username"))
	password := r.FormValue("password")

	if username == "" {
		s.render(w, http.StatusUnprocessableEntity, "register.html", authFormData{
			Base: Base{Title: "Register"}, Error: "Username is required.",
		})
		return
	}
	if err := auth.ValidatePassword(password); err != nil {
		s.render(w, http.StatusUnprocessableEntity, "register.html", authFormData{
			Base: Base{Title: "Register"}, Error: err.Error(),
		})
		return
	}

	hash, err := auth.HashPassword(password)
	if err != nil {
		s.log.Error("hash password", "error", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	userID, err := s.store.CreateUser(r.Context(), username, hash)
	if err != nil {
		s.render(w, http.StatusUnprocessableEntity, "register.html", authFormData{
			Base: Base{Title: "Register"}, Error: "That username is already taken.",
		})
		return
	}

	http.SetCookie(w, s.auth.NewSessionCookie(userID))
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func (s *Server) handleLoginForm(w http.ResponseWriter, r *http.Request) {
	if _, err := s.currentUser(r); err == nil {
		http.Redirect(w, r, "/", http.StatusSeeOther)
		return
	}
	s.render(w, http.StatusOK, "login.html", authFormData{Base: Base{Title: "Log in"}})
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	username := strings.TrimSpace(r.FormValue("username"))
	password := r.FormValue("password")

	user, err := s.store.GetUserByUsername(r.Context(), username)
	if errors.Is(err, store.ErrNotFound) || (err == nil && !auth.CheckPassword(user.PasswordHash, password)) {
		s.render(w, http.StatusUnauthorized, "login.html", authFormData{
			Base: Base{Title: "Log in"}, Error: "Invalid username or password.",
		})
		return
	}
	if err != nil {
		s.log.Error("get user", "error", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	http.SetCookie(w, s.auth.NewSessionCookie(user.ID))
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, auth.ClearSessionCookie())
	http.Redirect(w, r, "/login", http.StatusSeeOther)
}
