import {
  buildOauthProviderAuthResult,
  emptyPluginConfigSchema,
  type OpenClawPluginApi,
  type ProviderAuthContext,
} from "openclaw/plugin-sdk";
import { loginAntigravityOAuth } from "./oauth.js";

const PROVIDER_ID = "google-antigravity";
const PROVIDER_LABEL = "Google Antigravity OAuth";
const DEFAULT_MODEL = "google-antigravity/gemini-3-pro-high";

const antigravityPlugin = {
  id: "google-antigravity-auth",
  name: "Google Antigravity Auth",
  description:
    "OAuth flow for Google Antigravity (Gemini 3, Claude, GPT-OSS via Google One subscription)",
  configSchema: emptyPluginConfigSchema(),
  register(api: OpenClawPluginApi) {
    api.registerProvider({
      id: PROVIDER_ID,
      label: PROVIDER_LABEL,
      docsPath: "/providers/models",
      aliases: ["antigravity"],
      envVars: [],
      auth: [
        {
          id: "oauth",
          label: "Google One OAuth",
          hint: "PKCE + localhost callback (port 51121)",
          kind: "oauth",
          run: async (ctx: ProviderAuthContext) => {
            const spin = ctx.prompter.progress("Starting Antigravity OAuth…");
            try {
              const result = await loginAntigravityOAuth({
                isRemote: ctx.isRemote,
                openUrl: ctx.openUrl,
                log: (msg) => ctx.runtime.log(msg),
                note: ctx.prompter.note,
                prompt: async (message) => String(await ctx.prompter.text({ message })),
                progress: spin,
              });

              spin.stop("Antigravity OAuth complete");
              return buildOauthProviderAuthResult({
                providerId: PROVIDER_ID,
                defaultModel: DEFAULT_MODEL,
                access: result.access,
                refresh: result.refresh,
                expires: result.expires,
                email: result.email,
                credentialExtra: { projectId: result.projectId },
                notes: [
                  "Models available: Gemini 3 Pro (High/Low), Gemini 3 Flash, Claude Sonnet 4.6, Claude Opus 4.6, GPT-OSS 120B.",
                  "Quota refreshes monthly with your Google One subscription.",
                ],
              });
            } catch (err) {
              spin.stop("Antigravity OAuth failed");
              await ctx.prompter.note(
                "Trouble with OAuth? Ensure your Google account has an active Google One subscription with AI Premium.",
                "OAuth help",
              );
              throw err;
            }
          },
        },
      ],
    });
  },
};

export default antigravityPlugin;
