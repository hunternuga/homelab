// Package store wraps SQLite access for kcal's users and food-log entries.
package store

import (
	"context"
	"database/sql"
	_ "embed"
	"errors"
	"fmt"
	"time"

	_ "modernc.org/sqlite"
)

//go:embed schema.sql
var schema string

var ErrNotFound = errors.New("not found")

type Store struct {
	db *sql.DB
}

// Open opens (creating if necessary) the SQLite database at path and
// applies the schema. SQLite only supports one writer at a time, so the
// pool is capped at a single connection to avoid "database is locked"
// errors under concurrent requests.
func Open(ctx context.Context, path string) (*Store, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=foreign_keys(1)")
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}
	db.SetMaxOpenConns(1)

	if _, err := db.ExecContext(ctx, schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("apply schema: %w", err)
	}

	return &Store{db: db}, nil
}

func (s *Store) Close() error {
	return s.db.Close()
}

type User struct {
	ID           int64
	Username     string
	PasswordHash string
}

func (s *Store) CreateUser(ctx context.Context, username, passwordHash string) (int64, error) {
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO users (username, password_hash) VALUES (?, ?)`,
		username, passwordHash,
	)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) GetUserByUsername(ctx context.Context, username string) (*User, error) {
	var u User
	err := s.db.QueryRowContext(ctx,
		`SELECT id, username, password_hash FROM users WHERE username = ?`,
		username,
	).Scan(&u.ID, &u.Username, &u.PasswordHash)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (s *Store) GetUser(ctx context.Context, id int64) (*User, error) {
	var u User
	err := s.db.QueryRowContext(ctx,
		`SELECT id, username, password_hash FROM users WHERE id = ?`,
		id,
	).Scan(&u.ID, &u.Username, &u.PasswordHash)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

type Entry struct {
	ID          int64
	LoggedAt    string // YYYY-MM-DD
	Description string
	Calories    int
	ProteinG    float64
	CarbsG      float64
	FatG        float64
}

type Totals struct {
	Calories int
	ProteinG float64
	CarbsG   float64
	FatG     float64
}

func (s *Store) AddEntry(ctx context.Context, userID int64, e Entry) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO entries (user_id, logged_at, description, calories, protein_g, carbs_g, fat_g)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		userID, e.LoggedAt, e.Description, e.Calories, e.ProteinG, e.CarbsG, e.FatG,
	)
	return err
}

func (s *Store) DeleteEntry(ctx context.Context, userID, entryID int64) error {
	res, err := s.db.ExecContext(ctx,
		`DELETE FROM entries WHERE id = ? AND user_id = ?`,
		entryID, userID,
	)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// EntriesForDate returns all entries a user logged on the given date
// (YYYY-MM-DD), most recent first.
func (s *Store) EntriesForDate(ctx context.Context, userID int64, date string) ([]Entry, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, logged_at, description, calories, protein_g, carbs_g, fat_g
		 FROM entries WHERE user_id = ? AND logged_at = ?
		 ORDER BY id DESC`,
		userID, date,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanEntries(rows)
}

func scanEntries(rows *sql.Rows) ([]Entry, error) {
	var entries []Entry
	for rows.Next() {
		var e Entry
		if err := rows.Scan(&e.ID, &e.LoggedAt, &e.Description, &e.Calories, &e.ProteinG, &e.CarbsG, &e.FatG); err != nil {
			return nil, err
		}
		entries = append(entries, e)
	}
	return entries, rows.Err()
}

func TotalsFor(entries []Entry) Totals {
	var t Totals
	for _, e := range entries {
		t.Calories += e.Calories
		t.ProteinG += e.ProteinG
		t.CarbsG += e.CarbsG
		t.FatG += e.FatG
	}
	return t
}

// DayTotal is one day's aggregate totals, used for the history view.
type DayTotal struct {
	Date   string
	Totals Totals
}

// RecentDays returns per-day totals for the last n days (including days
// with no entries omitted), most recent first.
func (s *Store) RecentDays(ctx context.Context, userID int64, since time.Time) ([]DayTotal, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT logged_at, SUM(calories), SUM(protein_g), SUM(carbs_g), SUM(fat_g)
		 FROM entries
		 WHERE user_id = ? AND logged_at >= ?
		 GROUP BY logged_at
		 ORDER BY logged_at DESC`,
		userID, since.Format("2006-01-02"),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var days []DayTotal
	for rows.Next() {
		var d DayTotal
		if err := rows.Scan(&d.Date, &d.Totals.Calories, &d.Totals.ProteinG, &d.Totals.CarbsG, &d.Totals.FatG); err != nil {
			return nil, err
		}
		days = append(days, d)
	}
	return days, rows.Err()
}
