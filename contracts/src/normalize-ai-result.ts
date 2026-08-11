const sparkDevelopmentFields = [
  "premise",
  "audience",
  "creativeGoal",
  "proofOrStory",
  "desiredTakeaway",
  "constraints",
] as const;

type SparkDevelopmentField = (typeof sparkDevelopmentFields)[number];

const sparkNextSteps = new Set([
  "answerQuestion",
  "composeNow",
  "reviewWorkingState",
]);

/**
 * Converts harmless provider variance into the canonical result shape before
 * strict contract validation. Invalid generations still fail closed.
 */
export function normalizeAiOperationResult(
  operation: string,
  rawResult: unknown,
  requestPayload?: unknown,
): unknown {
  if (operation !== "sparkTurn" && operation !== "spark_turn") return rawResult;

  const candidate = unwrapResult(rawResult);
  if (!isRecord(candidate)) return rawResult;

  const assistantMessage = readText(
    candidate.assistantMessage,
    candidate.message,
    candidate.response,
    candidate.content,
  );
  if (assistantMessage === null) return rawResult;

  const request = isRecord(requestPayload) ? requestPayload : {};
  const requestWorkingState = normalizeWorkingState(request.workingState, emptyWorkingState());
  const workingState = normalizeWorkingState(candidate.workingState, requestWorkingState);
  const readyToCompose = candidate.readyToCompose === true;
  const focusedQuestion = readNullableText(candidate.focusedQuestion);
  const requestedNextStep = typeof candidate.recommendedNextStep === "string"
    ? candidate.recommendedNextStep
    : null;
  const recommendedNextStep = requestedNextStep && sparkNextSteps.has(requestedNextStep)
    ? requestedNextStep
    : readyToCompose
      ? "composeNow"
      : "answerQuestion";

  return {
    assistantMessage,
    focusedQuestion,
    recommendedNextStep,
    readyToCompose,
    missingFields: normalizeMissingFields(candidate.missingFields, workingState),
    workingState,
  };
}

function unwrapResult(rawResult: unknown): unknown {
  if (typeof rawResult === "string") {
    const parsed = parseJson(rawResult);
    return parsed ?? rawResult;
  }
  if (!isRecord(rawResult)) return rawResult;

  const content = rawResult.content;
  if (Array.isArray(content)) {
    for (const block of content) {
      if (!isRecord(block) || typeof block.text !== "string") continue;
      const parsed = parseJson(block.text);
      if (parsed !== undefined) return unwrapResult(parsed);
    }
  }

  for (const key of ["result", "output", "data"] as const) {
    const nested = rawResult[key];
    if (isRecord(nested)) return unwrapResult(nested);
    if (typeof nested === "string") {
      const parsed = parseJson(nested);
      if (parsed !== undefined) return unwrapResult(parsed);
    }
  }
  return rawResult;
}

function parseJson(value: string): unknown | undefined {
  const trimmed = value.trim();
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i)?.[1];
  for (const candidate of [fenced, trimmed]) {
    if (!candidate) continue;
    try {
      return JSON.parse(candidate) as unknown;
    } catch {
      // Continue to the next safe representation.
    }
  }
  return undefined;
}

function normalizeWorkingState(
  value: unknown,
  fallback: ReturnType<typeof emptyWorkingState>,
): ReturnType<typeof emptyWorkingState> {
  if (!isRecord(value)) return fallback;
  return {
    premise: readDevelopmentText(value.premise) ?? fallback.premise,
    audience: readDevelopmentText(value.audience) ?? fallback.audience,
    creativeGoal: readDevelopmentText(value.creativeGoal) ?? fallback.creativeGoal,
    proofOrStory: readDevelopmentText(value.proofOrStory) ?? fallback.proofOrStory,
    desiredTakeaway: readDevelopmentText(value.desiredTakeaway) ?? fallback.desiredTakeaway,
    constraints: readStringArray(value.constraints, 10) ?? fallback.constraints,
  };
}

function emptyWorkingState() {
  return {
    premise: null as string | null,
    audience: null as string | null,
    creativeGoal: null as string | null,
    proofOrStory: null as string | null,
    desiredTakeaway: null as string | null,
    constraints: [] as string[],
  };
}

function normalizeMissingFields(
  value: unknown,
  state: ReturnType<typeof emptyWorkingState>,
): SparkDevelopmentField[] {
  if (Array.isArray(value)) {
    return [...new Set(value.filter(
      (field): field is SparkDevelopmentField =>
        typeof field === "string"
        && sparkDevelopmentFields.includes(field as SparkDevelopmentField),
    ))].slice(0, 6);
  }

  return sparkDevelopmentFields.filter((field) =>
    field === "constraints" ? state.constraints.length === 0 : state[field] === null,
  );
}

function readText(...values: unknown[]): string | null {
  for (const value of values) {
    if (typeof value === "string") {
      const trimmed = value.trim();
      if (trimmed.length > 0) return trimmed.slice(0, 20_000);
    }
    if (Array.isArray(value)) {
      const joined = value
        .map((item) => isRecord(item) && typeof item.text === "string" ? item.text.trim() : "")
        .filter(Boolean)
        .join("\n");
      if (joined.length > 0) return joined.slice(0, 20_000);
    }
  }
  return null;
}

function readNullableText(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed.slice(0, 2_000) : null;
}

function readDevelopmentText(value: unknown): string | null | undefined {
  if (value === null) return null;
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed.slice(0, 2_000) : undefined;
}

function readStringArray(value: unknown, maximum: number): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, maximum)
    .map((item) => item.slice(0, 2_000));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
