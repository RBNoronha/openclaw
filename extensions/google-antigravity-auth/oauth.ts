import { loginAntigravity } from "@mariozechner/pi-ai/dist/utils/oauth/google-antigravity.js";
import { isWSL2Sync } from "openclaw/plugin-sdk";

export type AntigravityOAuthCredentials = {
  access: string;
  refresh: string;
  expires: number;
  email?: string;
  projectId: string;
};

export type AntigravityOAuthContext = {
  isRemote: boolean;
  openUrl: (url: string) => Promise<void>;
  log: (msg: string) => void;
  note: (message: string, title?: string) => Promise<void>;
  prompt: (message: string) => Promise<string>;
  progress: { update: (msg: string) => void; stop: (msg?: string) => void };
};

function shouldUseManualOAuthFlow(isRemote: boolean): boolean {
  return isRemote || isWSL2Sync();
}

export async function loginAntigravityOAuth(
  ctx: AntigravityOAuthContext,
): Promise<AntigravityOAuthCredentials> {
  const needsManual = shouldUseManualOAuthFlow(ctx.isRemote);

  await ctx.note(
    needsManual
      ? [
          "You are running in a remote/VPS environment.",
          "A URL will be shown for you to open in your LOCAL browser.",
          "After signing in, copy the full redirect URL and paste it back here.",
        ].join("\n")
      : [
          "Browser will open for Google authentication.",
          "Sign in with your Google One account for Antigravity access.",
          "The OAuth callback will be captured on localhost:51121.",
        ].join("\n"),
    "Google Antigravity OAuth",
  );

  ctx.progress.update("Starting Antigravity OAuth…");

  const credentials = await loginAntigravity(
    ({ url, instructions }) => {
      if (needsManual) {
        ctx.progress.update("OAuth URL ready");
        ctx.log(`\nOpen this URL in your LOCAL browser:\n\n${url}\n`);
        if (instructions) {
          ctx.log(instructions);
        }
      } else {
        ctx.progress.update("Complete sign-in in browser…");
        ctx.openUrl(url).catch(() => {
          ctx.log(`\nOpen this URL in your browser:\n\n${url}\n`);
        });
      }
    },
    (msg) => ctx.progress.update(msg),
    needsManual
      ? async () => {
          ctx.progress.update("Waiting for you to paste the callback URL...");
          return ctx.prompt("Paste the redirect URL here: ");
        }
      : undefined,
  );

  return {
    access: credentials.access,
    refresh: credentials.refresh ?? "",
    expires: credentials.expires ?? 0,
    email: credentials.email,
    projectId: credentials.projectId ?? "",
  };
}
