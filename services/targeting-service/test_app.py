import unittest
import os

class TestTargetingServiceConfig(unittest.TestCase):
    def test_environment_variables(self):
        db_url = os.getenv("DATABASE_URL", "postgresql://user:pass@localhost:5432/targetingdb")
        auth_url = os.getenv("AUTH_SERVICE_URL", "http://localhost:8081")
        self.assertIsNotNone(db_url)
        self.assertIsNotNone(auth_url)

    def test_rule_structure(self):
        rule = {
            "flag_name": "NEW_FEATURE",
            "is_enabled": True,
            "rules": {"type": "PERCENTAGE", "value": 50}
        }
        self.assertEqual(rule["rules"]["type"], "PERCENTAGE")
        self.assertEqual(rule["rules"]["value"], 50)

if __name__ == "__main__":
    unittest.main()
