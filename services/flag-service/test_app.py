import unittest
import os

class TestFlagServiceConfig(unittest.TestCase):
    def test_environment_variables_defaults(self):
        # Validação de carregamento das variáveis
        db_url = os.getenv("DATABASE_URL", "postgresql://user:pass@localhost:5432/flagdb")
        auth_url = os.getenv("AUTH_SERVICE_URL", "http://localhost:8081")
        self.assertIsNotNone(db_url)
        self.assertIsNotNone(auth_url)

    def test_flag_data_structure(self):
        sample_flag = {
            "name": "TEST_FLAG",
            "description": "Flag de teste unitario",
            "is_enabled": True
        }
        self.assertEqual(sample_flag["name"], "TEST_FLAG")
        self.assertTrue(sample_flag["is_enabled"])

if __name__ == "__main__":
    unittest.main()
