package web

import "github.com/hunternuga/homelab/services/kcal/app/internal/store"

// Base holds fields every page template needs.
type Base struct {
	Title string
	User  *store.User
	Flash string
}

type authFormData struct {
	Base
	Error string
}

type dashboardData struct {
	Base
	Date    string
	Entries []store.Entry
	Totals  store.Totals
	Error   string
}

type historyData struct {
	Base
	Days       []store.DayTotal
	WeekTotals store.Totals
}
