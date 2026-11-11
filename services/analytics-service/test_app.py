import unittest
import os
import json

class TestAnalyticsServiceConfig(unittest.TestCase):
    def test_analytics_payload(self):
        sample_event = {
            "event_id": "evt-12345",
            "flag_name": "checkout_v2",
            "user_id": "user-999",
            "result": True,
            "timestamp": "2026-09-05T10:00:00Z"
        }
        encoded = json.dumps(sample_event)
        decoded = json.loads(encoded)
        self.assertEqual(decoded["event_id"], "evt-12345")
        self.assertTrue(decoded["result"])

    def test_aws_defaults(self):
        region = os.getenv("AWS_REGION", "us-east-1")
        self.assertEqual(region, "us-east-1")

if __name__ == "__main__":
    unittest.main()
