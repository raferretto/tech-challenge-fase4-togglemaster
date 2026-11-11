package main

import (
	"strings"
	"testing"
)

func TestNotFoundError(t *testing.T) {
	err := &NotFoundError{FlagName: "feature_dark_mode"}
	if !strings.Contains(err.Error(), "feature_dark_mode") {
		t.Errorf("Mensagem de erro esperada continha o nome da flag, obtido: %s", err.Error())
	}
}

func TestCombinedFlagInfo(t *testing.T) {
	flag := &Flag{
		ID:        1,
		Name:      "test-flag",
		IsEnabled: true,
	}
	rule := &TargetingRule{
		ID:        1,
		FlagName:  "test-flag",
		IsEnabled: true,
		Rules: Rule{
			Type:  "PERCENTAGE",
			Value: 50,
		},
	}

	info := CombinedFlagInfo{
		Flag: flag,
		Rule: rule,
	}

	if info.Flag.Name != "test-flag" || info.Rule.Rules.Type != "PERCENTAGE" {
		t.Errorf("Dados de CombinedFlagInfo inconsistentes: %+v", info)
	}
}
