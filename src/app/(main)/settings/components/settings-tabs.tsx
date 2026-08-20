import { SETTINGS_TABS, type SettingsTab } from "../settings-shared";

export function SettingsTabs({ active, onChange }: { active: SettingsTab; onChange: (tab: SettingsTab) => void }) {
  return (
    <div className="flex gap-1 rounded-2xl bg-white/50 p-1 shadow-[0_2px_8px_rgba(0,0,0,0.04)] backdrop-blur-2xl dark:bg-white/[0.06]">
      {SETTINGS_TABS.map((tab) => (
        <button
          key={tab.id}
          type="button"
          onClick={() => onChange(tab.id)}
          className={`flex-1 rounded-xl px-4 py-2.5 text-sm font-semibold transition-all ${
            active === tab.id
              ? "bg-white text-[#1c1c1e] shadow-[0_2px_8px_rgba(0,0,0,0.08)] dark:bg-white/[0.12] dark:text-white"
              : "text-secondary-label hover:text-[#1c1c1e] dark:text-secondary-label dark:hover:text-white"
          }`}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );
}
