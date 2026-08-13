// Package auth handles password hashing and signed session cookies.
package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
)

const (
	CookieName   = "kcal_session"
	sessionTTL   = 30 * 24 * time.Hour
	minPassword  = 8
)

var (
	ErrInvalidCredentials = errors.New("invalid username or password")
	ErrWeakPassword       = fmt.Errorf("password must be at least %d characters", minPassword)
	ErrInvalidSession      = errors.New("invalid or expired session")
)

func ValidatePassword(password string) error {
	if len(password) < minPassword {
		return ErrWeakPassword
	}
	return nil
}

func HashPassword(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

func CheckPassword(hash, password string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

// Manager issues and verifies signed session cookies. The secret is the
// operator-supplied SESSION_SECRET; losing it (or rotating it) invalidates
// all existing sessions, which is an acceptable tradeoff for a single-user
// self-hosted app in exchange for needing no server-side session store.
type Manager struct {
	secret []byte
}

func NewManager(secret string) *Manager {
	return &Manager{secret: []byte(secret)}
}

// NewSessionCookie returns a signed cookie encoding userID, valid for
// sessionTTL.
func (m *Manager) NewSessionCookie(userID int64) *http.Cookie {
	expiry := time.Now().Add(sessionTTL).Unix()
	payload := fmt.Sprintf("%d.%d", userID, expiry)
	sig := m.sign(payload)
	value := base64.RawURLEncoding.EncodeToString([]byte(payload + "." + sig))

	return &http.Cookie{
		Name:     CookieName,
		Value:    value,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Expires:  time.Now().Add(sessionTTL),
	}
}

func ClearSessionCookie() *http.Cookie {
	return &http.Cookie{
		Name:     CookieName,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		MaxAge:   -1,
	}
}

// UserID verifies a session cookie value and returns the encoded user ID.
func (m *Manager) UserID(cookieValue string) (int64, error) {
	raw, err := base64.RawURLEncoding.DecodeString(cookieValue)
	if err != nil {
		return 0, ErrInvalidSession
	}

	parts := strings.SplitN(string(raw), ".", 3)
	if len(parts) != 3 {
		return 0, ErrInvalidSession
	}
	userIDPart, expiryPart, sig := parts[0], parts[1], parts[2]

	expectedSig := m.sign(userIDPart + "." + expiryPart)
	if subtle.ConstantTimeCompare([]byte(sig), []byte(expectedSig)) != 1 {
		return 0, ErrInvalidSession
	}

	expiry, err := strconv.ParseInt(expiryPart, 10, 64)
	if err != nil || time.Now().Unix() > expiry {
		return 0, ErrInvalidSession
	}

	userID, err := strconv.ParseInt(userIDPart, 10, 64)
	if err != nil {
		return 0, ErrInvalidSession
	}

	return userID, nil
}

func (m *Manager) sign(payload string) string {
	mac := hmac.New(sha256.New, m.secret)
	mac.Write([]byte(payload))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
