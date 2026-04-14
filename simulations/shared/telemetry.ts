import { mkdirSync, writeFileSync } from "fs";
import { join } from "path";

export type TelemetryWriteResult<T> = {
  latestPath: string;
  timestampedPath: string;
  payload: T;
};

function timestampId(): string {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

export function writeTelemetrySnapshot<T>(name: string, payload: T): TelemetryWriteResult<T> {
  const dir = join(process.cwd(), "artifacts", "telemetry");
  mkdirSync(dir, { recursive: true });

  const latestPath = join(dir, `${name}_latest.json`);
  const timestampedPath = join(dir, `${name}_${timestampId()}.json`);
  const serialized = `${JSON.stringify(payload, null, 2)}\n`;

  writeFileSync(latestPath, serialized, "utf8");
  writeFileSync(timestampedPath, serialized, "utf8");

  return { latestPath, timestampedPath, payload };
}
