import hashlib
import hmac
import json
import os
import time
import unittest
from unittest import mock

os.environ["HMAC_SECRET"] = "segredo-de-teste"
os.environ["COOLDOWN_SECONDS"] = "300"

import app as sh  # noqa: E402


def firing_payload(alertname="EvaluationServiceHighErrorRate", status="firing", fingerprint="abc123",
                   starts_at="2026-11-10T20:00:00Z"):
    return {"status": status, "alerts": [{
        "status": status, "labels": {"alertname": alertname, "service": "evaluation-service"},
        "fingerprint": fingerprint, "startsAt": starts_at,
    }]}


def signed_headers(body, secret="segredo-de-teste", timestamp=None):
    timestamp = str(int(time.time())) if timestamp is None else str(timestamp)
    return {
        sh.SIGNATURE_HEADER: sh.expected_signature(secret, timestamp, body),
        sh.TIMESTAMP_HEADER: timestamp,
        "Content-Type": "application/json",
    }


class SelfHealingTest(unittest.TestCase):
    def setUp(self):
        sh._state["handled"].clear()
        sh._state["last_action_at"] = 0.0
        self.client = sh.app.test_client()
        self.restart = mock.patch.object(sh, "restart_deployment").start()
        mock.patch.object(sh, "watch_rollout").start()
        self.addCleanup(mock.patch.stopall)

    def post(self, payload, **kwargs):
        body = json.dumps(payload).encode()
        return self.client.post("/webhook/grafana", data=body, headers=signed_headers(body, **kwargs))

    def test_signature_matches_grafana_format(self):
        # HMAC-SHA256("<timestamp>:<corpo>") em hexadecimal, como em grafana/alerting http/hmac.go
        ref = hmac.new(b"k", b'1700000000:{"a":1}', hashlib.sha256).hexdigest()
        self.assertEqual(sh.expected_signature("k", "1700000000", b'{"a":1}'), ref)

    def test_valid_firing_alert_triggers_restart(self):
        response = self.post(firing_payload())
        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.get_json()["action"], "rollout_restart")
        self.restart.assert_called_once()

    def test_invalid_signature_is_rejected(self):
        response = self.post(firing_payload(), secret="outro-segredo")
        self.assertEqual(response.status_code, 401)
        self.restart.assert_not_called()

    def test_missing_signature_is_rejected(self):
        response = self.client.post("/webhook/grafana", json=firing_payload())
        self.assertEqual(response.status_code, 401)
        self.restart.assert_not_called()

    def test_old_timestamp_is_rejected(self):
        response = self.post(firing_payload(), timestamp=int(time.time()) - 3600)
        self.assertEqual(response.status_code, 401)
        self.restart.assert_not_called()

    def test_resolved_alert_is_ignored(self):
        response = self.post(firing_payload(status="resolved"))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["action"], "ignored")
        self.restart.assert_not_called()

    def test_other_alert_is_ignored(self):
        response = self.post(firing_payload(alertname="DatasourceError"))
        self.assertEqual(response.get_json()["action"], "ignored")
        self.restart.assert_not_called()

    def test_same_occurrence_is_handled_once(self):
        self.assertEqual(self.post(firing_payload()).status_code, 202)
        again = self.post(firing_payload())
        self.assertEqual(again.get_json()["action"], "ignored")
        self.assertEqual(self.restart.call_count, 1)

    def test_cooldown_blocks_a_new_occurrence(self):
        self.assertEqual(self.post(firing_payload()).status_code, 202)
        other = self.post(firing_payload(fingerprint="zzz999", starts_at="2026-11-10T20:03:00Z"))
        self.assertEqual(other.get_json()["action"], "ignored")
        self.assertIn("intervalo", other.get_json()["reason"])
        self.assertEqual(self.restart.call_count, 1)

    def test_rollout_finished(self):
        base = {"metadata": {"generation": 3}, "spec": {"replicas": 2}}
        done = dict(base, status={"observedGeneration": 3, "updatedReplicas": 2, "replicas": 2, "availableReplicas": 2})
        mid = dict(base, status={"observedGeneration": 3, "updatedReplicas": 1, "replicas": 3, "availableReplicas": 2})
        self.assertTrue(sh.rollout_finished(done))
        self.assertFalse(sh.rollout_finished(mid))


if __name__ == "__main__":
    unittest.main()
