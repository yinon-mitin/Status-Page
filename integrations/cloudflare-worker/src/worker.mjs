const SNS_TYPES = new Set([
  "Notification",
  "SubscriptionConfirmation",
  "UnsubscribeConfirmation",
]);

function readLength(bytes, offset) {
  const first = bytes[offset];
  if (first < 0x80) return { length: first, bytesRead: 1 };
  const count = first & 0x7f;
  if (count === 0 || count > 4) throw new Error("Unsupported ASN.1 length");
  let length = 0;
  for (let index = 0; index < count; index += 1) {
    length = (length << 8) | bytes[offset + 1 + index];
  }
  return { length, bytesRead: 1 + count };
}

function readTlv(bytes, offset) {
  const tag = bytes[offset];
  const decoded = readLength(bytes, offset + 1);
  const headerLength = 1 + decoded.bytesRead;
  const end = offset + headerLength + decoded.length;
  if (end > bytes.length) throw new Error("Truncated ASN.1 value");
  return { tag, start: offset, valueStart: offset + headerLength, end };
}

function certificateSpki(certificatePem) {
  const base64 = certificatePem
    .replace("-----BEGIN CERTIFICATE-----", "")
    .replace("-----END CERTIFICATE-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  const certificate = readTlv(bytes, 0);
  const tbs = readTlv(bytes, certificate.valueStart);
  let cursor = tbs.valueStart;
  let field = readTlv(bytes, cursor);
  if (field.tag === 0xa0) {
    cursor = field.end;
  }
  // serialNumber, signature, issuer, validity, subject
  for (let index = 0; index < 5; index += 1) {
    field = readTlv(bytes, cursor);
    cursor = field.end;
  }
  const spki = readTlv(bytes, cursor);
  if (spki.tag !== 0x30) throw new Error("SNS certificate has no SPKI sequence");
  return bytes.slice(spki.start, spki.end);
}

export function validateAwsSnsUrl(rawUrl) {
  const url = new URL(rawUrl);
  if (url.protocol !== "https:") throw new Error("SNS URL must use HTTPS");
  if (!/^sns\.[a-z0-9-]+\.amazonaws\.com(?:\.cn)?$/.test(url.hostname)) {
    throw new Error("SNS URL host is not allowlisted");
  }
  if (url.username || url.password || url.port) {
    throw new Error("SNS URL contains forbidden authority components");
  }
  return url;
}

export function canonicalMessage(message) {
  const fields = {
    Notification: ["Message", "MessageId", "Subject", "Timestamp", "TopicArn", "Type"],
    SubscriptionConfirmation: [
      "Message",
      "MessageId",
      "SubscribeURL",
      "Timestamp",
      "Token",
      "TopicArn",
      "Type",
    ],
    UnsubscribeConfirmation: [
      "Message",
      "MessageId",
      "SubscribeURL",
      "Timestamp",
      "Token",
      "TopicArn",
      "Type",
    ],
  }[message.Type];
  if (!fields) throw new Error("Unsupported SNS message type");
  return fields
    .filter((field) => message[field] !== undefined)
    .map((field) => `${field}\n${message[field]}\n`)
    .join("");
}

async function verifySnsMessage(message) {
  if (!SNS_TYPES.has(message.Type)) throw new Error("Unsupported SNS message type");
  if (!["1", "2"].includes(message.SignatureVersion)) {
    throw new Error("Unsupported SNS signature version");
  }
  const certificateUrl = validateAwsSnsUrl(message.SigningCertURL);
  if (!certificateUrl.pathname.endsWith(".pem")) {
    throw new Error("SNS signing certificate path is invalid");
  }
  const response = await fetch(certificateUrl.toString());
  if (!response.ok) throw new Error("SNS signing certificate fetch failed");
  const spki = certificateSpki(await response.text());
  const hash = message.SignatureVersion === "1" ? "SHA-1" : "SHA-256";
  const publicKey = await crypto.subtle.importKey(
    "spki",
    spki,
    { name: "RSASSA-PKCS1-v1_5", hash },
    false,
    ["verify"],
  );
  const signature = Uint8Array.from(atob(message.Signature), (character) =>
    character.charCodeAt(0),
  );
  return crypto.subtle.verify(
    { name: "RSASSA-PKCS1-v1_5" },
    publicKey,
    signature,
    new TextEncoder().encode(canonicalMessage(message)),
  );
}

function validateEnvironment(env) {
  for (const name of ["SNS_TOPIC_ARN", "TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID"]) {
    if (!env[name]) throw new Error(`Missing Worker binding: ${name}`);
  }
  if (!/^arn:aws:sns:il-central-1:992382545251:yinon-status-page-prod-alerts$/.test(env.SNS_TOPIC_ARN)) {
    throw new Error("SNS_TOPIC_ARN is outside the production alert scope");
  }
}

async function sendTelegram(message, env) {
  const alarm = (() => {
    try {
      return JSON.parse(message.Message);
    } catch (_error) {
      return null;
    }
  })();
  const heading = alarm?.AlarmName ? `AWS alarm: ${alarm.AlarmName}` : "AWS production alert";
  const detail = alarm?.NewStateReason || message.Subject || message.Message;
  const text = `${heading}\n\n${String(detail).slice(0, 3500)}\n\nTopic: ${message.TopicArn}`;
  const response = await fetch(
    `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ chat_id: env.TELEGRAM_CHAT_ID, text }),
    },
  );
  if (!response.ok) throw new Error("Telegram delivery failed");
}

export default {
  async fetch(request, env) {
    if (request.method === "GET") {
      return Response.json({ status: "ok", service: "status-page-alert-relay" });
    }
    if (request.method !== "POST") return new Response("Method Not Allowed", { status: 405 });
    const length = Number(request.headers.get("content-length") || "0");
    if (length > 300000) return new Response("Payload Too Large", { status: 413 });

    try {
      validateEnvironment(env);
      const message = await request.json();
      if (message.TopicArn !== env.SNS_TOPIC_ARN) throw new Error("Unexpected SNS topic");
      if (!(await verifySnsMessage(message))) throw new Error("Invalid SNS signature");

      if (message.Type === "SubscriptionConfirmation") {
        const subscribeUrl = validateAwsSnsUrl(message.SubscribeURL);
        const response = await fetch(subscribeUrl.toString());
        if (!response.ok) throw new Error("SNS subscription confirmation failed");
      } else if (message.Type === "Notification") {
        await sendTelegram(message, env);
      }
      return new Response("ok");
    } catch (_error) {
      return new Response("Unauthorized", { status: 401 });
    }
  },
};
