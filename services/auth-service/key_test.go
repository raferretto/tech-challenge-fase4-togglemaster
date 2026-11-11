package main

import (
	"strings"
	"testing"
)

func TestGenerateAPIKey(t *testing.T) {
	key, err := generateAPIKey()
	if err != nil {
		t.Fatalf("Erro inesperado ao gerar chave: %v", err)
	}

	if !strings.HasPrefix(key, "tm_key_") {
		t.Errorf("Chave gerada deve comecar com 'tm_key_', recebido: %s", key)
	}

	if len(key) <= len("tm_key_") {
		t.Errorf("Chave gerada muito curta: %s", key)
	}
}

func TestHashAPIKey(t *testing.T) {
	rawKey := "tm_key_abcdef1234567890"
	hash1 := hashAPIKey(rawKey)
	hash2 := hashAPIKey(rawKey)

	if hash1 != hash2 {
		t.Errorf("Hash SHA-256 deve ser deterministico: %s != %s", hash1, hash2)
	}

	if len(hash1) != 64 {
		t.Errorf("Tamanho do hash SHA-256 hexadecimal esperado 64, recebido %d", len(hash1))
	}
}
