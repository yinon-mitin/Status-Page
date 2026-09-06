import test from "node:test";
import assert from "node:assert/strict";
import {
  canonicalMessage,
  validateAwsSnsUrl,
  validateTimestamp,
} from "../src/worker.mjs";

test("builds AWS canonical notification payload", () => {
  assert.equal(
    canonicalMessage({
      Type: "Notification",
      Message: "alarm",
      MessageId: "id",
      Timestamp: "2026-01-01T00:00:00Z",
      TopicArn: "arn:aws:sns:il-central-1:992382545251:yinon-status-page-prod-alerts",
    }),
    "Message\nalarm\nMessageId\nid\nTimestamp\n2026-01-01T00:00:00Z\nTopicArn\narn:aws:sns:il-central-1:992382545251:yinon-status-page-prod-alerts\nType\nNotification\n",
  );
});

test("allows only regional AWS SNS HTTPS URLs", () => {
  assert.equal(
    validateAwsSnsUrl("https://sns.il-central-1.amazonaws.com/certificate.pem").hostname,
    "sns.il-central-1.amazonaws.com",
  );
  assert.throws(() => validateAwsSnsUrl("https://example.com/certificate.pem"));
  assert.throws(() => validateAwsSnsUrl("http://sns.il-central-1.amazonaws.com/certificate.pem"));
});

test("rejects stale and future SNS messages", () => {
  const now = Date.parse("2026-01-01T00:05:00Z");
  assert.doesNotThrow(() => validateTimestamp("2026-01-01T00:04:00Z", now));
  assert.throws(() => validateTimestamp("2025-12-31T23:55:00Z", now));
  assert.throws(() => validateTimestamp("2026-01-01T00:10:00Z", now));
});
