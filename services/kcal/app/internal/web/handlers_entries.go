package web

import (
	"net/http"
	"strconv"
	"time"

	"github.com/hunternuga/homelab/services/kcal/app/internal/store"
)

const dateFormat = "2006-01-02"

func (s *Server) handleDashboard(w http.ResponseWriter, r *http.Request) {
	user := userFromContext(r.Context())
	today := time.Now().Format(dateFormat)

	entries, err := s.store.EntriesForDate(r.Context(), user.ID, today)
	if err != nil {
		s.log.Error("list entries", "error", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	s.render(w, http.StatusOK, "dashboard.html", dashboardData{
		Base:    Base{Title: "Today", User: user},
		Date:    today,
		Entries: entries,
		Totals:  store.TotalsFor(entries),
	})
}

func (s *Server) handleAddEntry(w http.ResponseWriter, r *http.Request) {
	user := userFromContext(r.Context())

	description := r.FormValue("description")
	calories, calErr := strconv.Atoi(r.FormValue("calories"))
	protein, _ := strconv.ParseFloat(r.FormValue("protein_g"), 64)
	carbs, _ := strconv.ParseFloat(r.FormValue("carbs_g"), 64)
	fat, _ := strconv.ParseFloat(r.FormValue("fat_g"), 64)

	date := r.FormValue("logged_at")
	if date == "" {
		date = time.Now().Format(dateFormat)
	}

	if description == "" || calErr != nil || calories < 0 {
		entries, _ := s.store.EntriesForDate(r.Context(), user.ID, time.Now().Format(dateFormat))
		s.render(w, http.StatusUnprocessableEntity, "dashboard.html", dashboardData{
			Base:    Base{Title: "Today", User: user},
			Date:    time.Now().Format(dateFormat),
			Entries: entries,
			Totals:  store.TotalsFor(entries),
			Error:   "Enter a description and a non-negative calorie count.",
		})
		return
	}

	err := s.store.AddEntry(r.Context(), user.ID, store.Entry{
		LoggedAt:    date,
		Description: description,
		Calories:    calories,
		ProteinG:    protein,
		CarbsG:      carbs,
		FatG:        fat,
	})
	if err != nil {
		s.log.Error("add entry", "error", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func (s *Server) handleDeleteEntry(w http.ResponseWriter, r *http.Request) {
	user := userFromContext(r.Context())

	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		http.NotFound(w, r)
		return
	}

	if err := s.store.DeleteEntry(r.Context(), user.ID, id); err != nil {
		s.log.Error("delete entry", "error", err)
	}

	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func (s *Server) handleHistory(w http.ResponseWriter, r *http.Request) {
	user := userFromContext(r.Context())

	since := time.Now().AddDate(0, 0, -30)
	days, err := s.store.RecentDays(r.Context(), user.ID, since)
	if err != nil {
		s.log.Error("list history", "error", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	weekCutoff := time.Now().AddDate(0, 0, -7).Format(dateFormat)
	var weekTotals store.Totals
	for _, d := range days {
		if d.Date >= weekCutoff {
			weekTotals.Calories += d.Totals.Calories
			weekTotals.ProteinG += d.Totals.ProteinG
			weekTotals.CarbsG += d.Totals.CarbsG
			weekTotals.FatG += d.Totals.FatG
		}
	}

	s.render(w, http.StatusOK, "history.html", historyData{
		Base:       Base{Title: "History", User: user},
		Days:       days,
		WeekTotals: weekTotals,
	})
}
