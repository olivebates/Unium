export function displayScore(score: number, created: number, now = Date.now()): number {
  return now < created + 86_400_000 ? Math.max(0, score) : score;
}

// Reddit's original hot formula; time is seconds from Reddit's epoch.
export function hotScore(up: number, down: number, created: number): number {
  const score = up - down;
  return Math.sign(score) * Math.log10(Math.max(Math.abs(score), 1)) + (created / 1000 - 1134028003) / 45000;
}

export const periods: Record<string, number> = {
  Today: 86_400_000, Week: 7 * 86_400_000, Month: 30 * 86_400_000,
  Year: 365 * 86_400_000, "All time": Infinity, Hot: Infinity,
};
