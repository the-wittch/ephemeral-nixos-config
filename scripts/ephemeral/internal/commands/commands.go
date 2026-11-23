// Package commands is the list of helper commands and the words that reach each one. The list
// comes from the tools table in modules/packages/packages.nix, which the build writes to JSON.
package commands

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
)

type Command struct {
	Name        string   `json:"name"`
	Words       []string `json:"words"`
	Description string   `json:"description"`
	Minimal     bool     `json:"minimal"`
}

func (c Command) Usage() string { return "ephemeral " + strings.Join(c.Words, " ") }

func Load(path string) ([]Command, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("can't read the list of commands: %w", err)
	}
	var cs []Command
	if err := json.Unmarshal(data, &cs); err != nil {
		return nil, fmt.Errorf("can't read the list of commands in %s: %w", path, err)
	}
	sort.SliceStable(cs, func(i, j int) bool { return cs[i].Usage() < cs[j].Usage() })
	return cs, nil
}

// Find picks the command whose words start args, the longest first, and returns what follows.
func Find(cs []Command, args []string) (Command, []string, bool) {
	best, n := Command{}, 0
	for _, c := range cs {
		if len(c.Words) > len(args) || len(c.Words) <= n {
			continue
		}
		match := true
		for i, w := range c.Words {
			if args[i] != w {
				match = false
				break
			}
		}
		if match {
			best, n = c, len(c.Words)
		}
	}
	return best, args[n:], n > 0
}

// Group lists the commands under a first word, such as backup, when it isn't one by itself.
func Group(cs []Command, word string) []Command {
	var out []Command
	for _, c := range cs {
		if c.Words[0] == word {
			out = append(out, c)
		}
	}
	return out
}

// Nearest is the command the user most likely meant by a word that isn't one.
func Nearest(words []string, word string) string {
	best, score := "", 3
	for _, w := range words {
		if d := distance(w, word); d < score {
			best, score = w, d
		}
		if strings.HasPrefix(w, word) && len(word) >= 2 {
			return w
		}
	}
	return best
}

func distance(a, b string) int {
	prev := make([]int, len(b)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(a); i++ {
		cur := make([]int, len(b)+1)
		cur[0] = i
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			cur[j] = min(prev[j]+1, cur[j-1]+1, prev[j-1]+cost)
		}
		prev = cur
	}
	return prev[len(b)]
}
