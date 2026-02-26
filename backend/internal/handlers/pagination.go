package handlers

import (
	"strconv"
	"strings"
)

const (
	defaultPageLimit = 50
	maxPageLimit     = 200
)

type listQueryParams struct {
	Limit   int
	Offset  int
	Search  string
	Pattern string
}

func parseListQueryParams(
	rawLimit string,
	rawOffset string,
	rawSearch string,
	defaultLimit int,
	maxLimit int,
) listQueryParams {
	limit := defaultLimit
	if parsedLimit, err := strconv.Atoi(strings.TrimSpace(rawLimit)); err == nil && parsedLimit > 0 {
		limit = parsedLimit
	}
	if limit <= 0 {
		limit = defaultPageLimit
	}
	if maxLimit > 0 && limit > maxLimit {
		limit = maxLimit
	}

	offset := 0
	if parsedOffset, err := strconv.Atoi(strings.TrimSpace(rawOffset)); err == nil && parsedOffset >= 0 {
		offset = parsedOffset
	}

	search := strings.TrimSpace(rawSearch)
	pattern := ""
	if search != "" {
		pattern = "%" + strings.ToLower(search) + "%"
	}

	return listQueryParams{
		Limit:   limit,
		Offset:  offset,
		Search:  search,
		Pattern: pattern,
	}
}
