import { describe, expect, it } from "vitest";

import { functionsProjectId, notificationChannel } from "../../src/slack";

describe("notificationChannel", () => {
  it("snapmon-prod なら本番のチャンネル", () => {
    expect(notificationChannel("snapmon-prod")).toBe("#snapmon-notification");
  });

  it("別のプロジェクト ID なら -qa のチャンネル", () => {
    expect(notificationChannel("demo-snapmon")).toBe("#snapmon-notification-qa");
  });

  it("空文字なら -qa のチャンネル", () => {
    expect(notificationChannel("")).toBe("#snapmon-notification-qa");
  });
});

describe("functionsProjectId", () => {
  it("GCLOUD_PROJECT を優先する", () => {
    expect(
      functionsProjectId({ GCLOUD_PROJECT: "snapmon-prod", FIREBASE_CONFIG: JSON.stringify({ projectId: "demo-snapmon" }) }),
    ).toBe("snapmon-prod");
  });

  it("GCLOUD_PROJECT が無ければ FIREBASE_CONFIG の projectId を使う", () => {
    expect(functionsProjectId({ FIREBASE_CONFIG: JSON.stringify({ projectId: "snapmon-prod" }) })).toBe("snapmon-prod");
  });

  it("どちらも無ければ空文字", () => {
    expect(functionsProjectId({})).toBe("");
  });

  it("FIREBASE_CONFIG が JSON でなければ空文字", () => {
    expect(functionsProjectId({ FIREBASE_CONFIG: "{" })).toBe("");
  });
});
