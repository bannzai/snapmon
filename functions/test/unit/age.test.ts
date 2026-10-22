import { describe, expect, it } from "vitest";

import { hasReachedMinimumAge } from "../../src/age";

describe("hasReachedMinimumAge", () => {
  const now = new Date(Date.UTC(2026, 9, 21));

  it("13 歳の誕生月を過ぎていれば通す", () => {
    expect(hasReachedMinimumAge({ birthYear: 2013, birthMonth: 9, now })).toBe(true);
  });

  it("13 歳の誕生月の中は、誕生日の前か後かを決められないため通さない", () => {
    expect(hasReachedMinimumAge({ birthYear: 2013, birthMonth: 10, now })).toBe(false);
  });

  it("13 歳未満は通さない", () => {
    expect(hasReachedMinimumAge({ birthYear: 2015, birthMonth: 1, now })).toBe(false);
  });

  it("成人は通す", () => {
    expect(hasReachedMinimumAge({ birthYear: 1990, birthMonth: 12, now })).toBe(true);
  });

  it("月の範囲外・整数でない値は通さない", () => {
    expect(hasReachedMinimumAge({ birthYear: 1990, birthMonth: 0, now })).toBe(false);
    expect(hasReachedMinimumAge({ birthYear: 1990, birthMonth: 13, now })).toBe(false);
    expect(hasReachedMinimumAge({ birthYear: 1990.5, birthMonth: 1, now })).toBe(false);
  });

  it("未来の生年月は通さない", () => {
    expect(hasReachedMinimumAge({ birthYear: 2030, birthMonth: 1, now })).toBe(false);
  });
});
