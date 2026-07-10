const APP_STORE_URL = 'https://apps.apple.com/us/app/farlo/id6781018329';
// Best guess from the real Android applicationId (android/app/build.gradle.kts:
// "com.farlo.app") -- no real Play Store URL exists anywhere in the repo yet
// (the marketing site's own button is still a "#" placeholder). CONFIRM this
// resolves to the real listing before shipping.
const GOOGLE_PLAY_URL = 'https://play.google.com/store/apps/details?id=com.farlo.app';

export function DownloadCta() {
  return (
    <div className="flex flex-wrap items-center justify-center gap-3">
      <a
        href={APP_STORE_URL}
        target="_blank"
        rel="noreferrer"
        className="rounded-lg bg-[var(--text)] px-5 py-2.5 text-sm font-medium text-white transition hover:opacity-90"
      >
        Download on the App Store
      </a>
      <a
        href={GOOGLE_PLAY_URL}
        target="_blank"
        rel="noreferrer"
        className="rounded-lg border border-[var(--border)] bg-white px-5 py-2.5 text-sm font-medium text-[var(--text)] transition hover:bg-[var(--bg)]"
      >
        Get it on Google Play
      </a>
    </div>
  );
}
