import type {
  ChatTurnRequest,
  ComposeBriefRequest,
  IdeasRequest,
  ReviseBriefRequest,
  RhythmProposalRequest,
  SparkTurnRequest,
  TasksProposalRequest,
  VoiceProfileRequest,
} from "@agent-cy/contracts";
import type { AiOperation } from "./store.js";

const as = <T>(value: unknown): T => value as T;

export const developmentFixtures: Partial<Record<AiOperation, (body: unknown) => unknown>> = {
  voice_profile: (body) => {
    const request = as<VoiceProfileRequest>(body);
    return {
      profile: {
        summary: `${request.creatorContext.name} communicates with direct, practical clarity.`,
        tone: ["grounded", "conversational"],
        sentenceStyle: "Clear sentences with natural spoken rhythm.",
        signatureQualities: ["specific", "useful", "human"],
        phrasesToUse: [],
        phrasesToAvoid: [],
        guidance: ["Open with the concrete point", "Prefer lived detail over hype"],
        confidence: request.creatorContext.voiceExamples.length >= 3 ? 0.78 : 0.55,
      },
      assumptions: ["The supplied examples represent the creator’s current voice."],
      evidenceNotes: ["Traits were extracted only from the supplied examples."],
    };
  },
  ideas: (body) => {
    const request = as<IdeasRequest>(body);
    const topic = request.startingPoint ?? request.creatorContext.primaryGoal;
    const suggestedPillarId = request.creatorContext.pillars[0]?.pillarId ?? null;
    return {
      ideas: [
        {
          directionId: "practical-breakdown",
          title: "The practical breakdown",
          premise: `Turn ${topic} into one useful, concrete lesson.`,
          opening: "Here’s the part I wish someone had made simpler.",
          whyItFits: "It uses a direct, teaching-led format.",
          assumedTakeaway: "The viewer leaves knowing one next move.",
          suggestedPillarId,
          assumptions: ["The creator has a firsthand lesson to share."],
        },
        {
          directionId: "before-after",
          title: "Before I understood this",
          premise: `Contrast an old belief about ${topic} with what changed.`,
          opening: "I used to think this was the hard part. It wasn’t.",
          whyItFits: "It creates a clear story turn without manufacturing drama.",
          assumedTakeaway: "The viewer can avoid the creator’s earlier mistake.",
          suggestedPillarId,
          assumptions: ["There is an honest before-and-after insight available."],
        },
        {
          directionId: "one-decision",
          title: "The one decision",
          premise: `Frame ${topic} around one decision the viewer can make today.`,
          opening: "If you only change one thing, make it this.",
          whyItFits: "It is focused enough for a short, executable video.",
          assumedTakeaway: "The viewer remembers a single decision rule.",
          suggestedPillarId,
          assumptions: ["The topic can be narrowed to one responsible recommendation."],
        },
      ],
    };
  },
  spark_turn: (body) => {
    const request = as<SparkTurnRequest>(body);
    const complete =
      request.composeNow ||
      (request.workingState.premise !== null &&
        request.workingState.audience !== null &&
        request.workingState.desiredTakeaway !== null);
    return {
      assistantMessage: complete
        ? "There is enough here to compose a useful first version. I’ll keep the remaining assumptions visible."
        : "Let’s sharpen the one detail that will make this useful rather than generic.",
      focusedQuestion: complete
        ? null
        : "Who should recognize themselves in the first five seconds?",
      recommendedNextStep: complete ? "composeNow" : "answerQuestion",
      readyToCompose: complete,
      missingFields: complete ? [] : ["audience"],
      workingState: {
        ...request.workingState,
        premise: request.workingState.premise ?? request.spark.text,
      },
    };
  },
  compose_brief: (body) => {
    const request = as<ComposeBriefRequest>(body);
    return {
      brief: {
        briefId: request.briefId,
        title: "A clear next move",
        premise: request.workingState.premise ?? request.spark.text,
        audience: request.workingState.audience ?? "Creators working through this problem",
        creativeGoal: request.workingState.creativeGoal ?? "Make the idea practical",
        desiredTakeaway:
          request.workingState.desiredTakeaway ?? "One clear next step",
        durationSeconds: request.durationSeconds,
        spokenHook: "Here’s the part I wish someone had made simpler.",
        firstFrameText: "Make the next move simpler",
        scriptBeats: [
          {
            order: 0,
            label: "Set up",
            purpose: "Name the recognizable problem",
            script: "Start with the exact moment this becomes harder than it needs to be.",
          },
          {
            order: 1,
            label: "Shift",
            purpose: "Deliver the useful reframe",
            script: "Explain the one decision that made the path clearer.",
          },
          {
            order: 2,
            label: "Apply",
            purpose: "Give the viewer a next move",
            script: "End with the smallest way to put the idea into practice today.",
          },
        ],
        close: "Choose the smallest version you can actually make.",
        ctaIntent: "Invite the viewer to try the next move",
        filmingGuidance: {
          setup: "Simple talking-head setup near a window",
          shots: ["Medium shot for the hook", "Slight punch-in for the reframe"],
          bRoll: ["One concrete example of the work in progress"],
          delivery: "Speak naturally, with a short pause before the reframe.",
          editing: "Use clean cuts between beats; keep the pacing calm.",
          audio: "Prioritize clear voice audio; music is optional.",
          onScreenText: ["The problem", "The shift", "Your next move"],
        },
        proposedTasks: [
          {
            title: "Review the brief",
            kind: "scripting",
            notes: "Make any final phrasing changes before filming.",
            estimatedMinutes: 10,
            isRecordingMilestone: false,
            order: 0,
          },
          {
            title: "Record the video",
            kind: "filming",
            notes: "Capture one complete take before adding coverage.",
            estimatedMinutes: 25,
            isRecordingMilestone: true,
            order: 1,
          },
        ],
        assumptions: ["The creator wants a useful, conversational delivery."],
        voiceConfidence: 0.72,
        platformVariants: request.selectedPlatforms.map((platform) => ({
          platform,
          caption: "A clear next move beats a perfect plan.",
          editChanges: [],
        })),
      },
    };
  },
  revise_brief: (body) => {
    const request = as<ReviseBriefRequest>(body);
    const brief = structuredClone(request.brief);
    reviseFixtureField(brief, request.scope);
    return {
      brief,
      changedFields: [request.scope],
      explanation: "Prepared the scoped revision for the creator to review and accept.",
    };
  },
  chat_turn: (body) => {
    const request = as<ChatTurnRequest>(body);
    return {
      assistantMessage: `I can help shape the next content decision for ${request.creatorContext.name}. Nothing changes until you accept it.`,
      suggestions: [
        { label: "Develop a spark", prompt: "Help me sharpen the idea I’m considering." },
      ],
      proposedAction: null,
    };
  },
  rhythm_proposal: (body) => {
    const request = as<RhythmProposalRequest>(body);
    const weekday = request.preferredWeekdays[0] ?? 2;
    return {
      name: "Simple weekly rhythm",
      rationale: "A small repeatable block protects creation time without rigid deadlines.",
      slots: [
        {
          weekday,
          startMinute: 600,
          durationMinutes: Math.min(90, request.availableMinutesPerWeek),
          kind: "filming",
          label: "Create one ready video",
        },
      ],
      assumptions: ["The proposed time is a flexible starting point."],
    };
  },
  tasks_proposal: (body) => {
    const request = as<TasksProposalRequest>(body);
    return {
      tasks: request.brief.proposedTasks,
      rationale: "These are the minimum steps needed to move the brief into production.",
    };
  },
};

function reviseFixtureField(
  brief: ReviseBriefRequest["brief"],
  scope: ReviseBriefRequest["scope"],
): void {
  const revised = (value: string, max = 2_000) =>
    `${value.replace(/\s+$/, "")} Refined.`.slice(0, max);
  switch (scope) {
    case "title":
      brief.title = revised(brief.title, 160);
      return;
    case "premise":
    case "audience":
    case "creativeGoal":
    case "desiredTakeaway":
    case "spokenHook":
    case "firstFrameText":
    case "close":
    case "ctaIntent":
      brief[scope] = revised(brief[scope]);
      return;
    case "durationSeconds": {
      const durations = (brief.durationSeconds >= 120
        ? [180, 300, 480, 600, 900]
        : [15, 30, 45, 60, 90]) as Array<typeof brief.durationSeconds>;
      const index = durations.indexOf(brief.durationSeconds);
      brief.durationSeconds = durations[(index + 1) % durations.length] ?? 45;
      return;
    }
    case "scriptBeats":
      brief.scriptBeats[0]!.script = revised(brief.scriptBeats[0]!.script, 20_000);
      return;
    case "filmingGuidance":
      brief.filmingGuidance.delivery = revised(brief.filmingGuidance.delivery);
      return;
    case "proposedTasks":
      brief.proposedTasks[0]!.title = revised(brief.proposedTasks[0]!.title, 160);
      return;
    case "assumptions":
      if (brief.assumptions.length < 10) {
        brief.assumptions.push("The scoped revision remains creator-approved before persistence.");
      } else {
        brief.assumptions[0] = revised(brief.assumptions[0]!);
      }
      return;
    case "platformVariants": {
      const variant = brief.platformVariants[0]!;
      variant.caption = revised(variant.caption ?? "Platform-specific caption", 20_000);
      return;
    }
    case "wholeBrief":
      brief.title = revised(brief.title, 160);
      return;
  }
}
