package explorer

import tea "github.com/charmbracelet/bubbletea"

// Run opens the explorer, reading everything from `engine persistence --children`.
func Run(engine string) error {
	_, err := tea.NewProgram(newModel(engineLoader(engine)), tea.WithAltScreen()).Run()
	return err
}
