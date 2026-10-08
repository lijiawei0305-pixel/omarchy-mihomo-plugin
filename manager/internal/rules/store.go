package rules

import (
	"encoding/json"
	"os"

	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/store"
)

func Load(s *store.Store) (Collection, error) {
	b, err := os.ReadFile(s.CustomRulesPath())
	if os.IsNotExist(err) {
		return DefaultCollection(), nil
	}
	if err != nil {
		return Collection{}, err
	}
	collection := DefaultCollection()
	if err := json.Unmarshal(b, &collection); err != nil {
		return Collection{}, err
	}
	return NormalizeCollection(collection)
}

func Save(s *store.Store, collection Collection) error {
	normalized, err := NormalizeCollection(collection)
	if err != nil {
		return err
	}
	b, err := json.MarshalIndent(normalized, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	return s.WriteAtomic(s.CustomRulesPath(), b)
}

func Clone(collection Collection) Collection {
	items := make([]Rule, len(collection.Rules))
	copy(items, collection.Rules)
	collection.Rules = items
	return collection
}

func Find(collection Collection, id string) (int, Rule, bool) {
	for i, item := range collection.Rules {
		if item.ID == id {
			return i, item, true
		}
	}
	return -1, Rule{}, false
}
