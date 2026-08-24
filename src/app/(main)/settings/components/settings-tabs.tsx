import { Segmented } from "@/components/ui";
import { SETTINGS_TABS, type SettingsTab } from "../settings-shared";

export function SettingsTabs({ active, onChange }: { active: SettingsTab; onChange: (tab: SettingsTab) => void }) {
  return (
    <Segmented
      className="flex w-full"
      value={active}
      onChange={onChange}
      options={SETTINGS_TABS.map((tab) => ({ value: tab.id, label: tab.label }))}
    />
  );
}
