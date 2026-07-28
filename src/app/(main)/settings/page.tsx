"use client";

import { useState } from "react";
import { Loader2, RefreshCw, Save } from "lucide-react";
import { Button, PageHeader } from "@/components/ui";
import { AiSettingsTab } from "./components/ai-settings-tab";
import { DataSettingsTab } from "./components/data-settings-tab";
import { ModelPickerDialog } from "./components/model-picker-dialog";
import { SettingsTabs } from "./components/settings-tabs";
import { StudySettingsTab } from "./components/study-settings-tab";
import { FeedbackBanner, type SettingsTab } from "./settings-shared";
import { useLlmSettings } from "./use-llm-settings";
import { useSettingsData } from "./use-settings-data";

export default function SettingsPage() {
  const [activeTab, setActiveTab] = useState<SettingsTab>("study");
  const data = useSettingsData();
  const llm = useLlmSettings(data.settings, data.setSettings);
  const pickerProvider = llm.modelPicker && data.settings
    ? data.settings.llmConfig.providers[llm.modelPicker.providerIndex]
    : null;

  return (
    <div className="space-y-6">
      <PageHeader
        title="设置与数据"
        description="调整每日学习计划、词典来源，并管理完整备份。"
        action={
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => void data.load()}><RefreshCw className="size-4" />刷新</Button>
            <Button onClick={() => void data.save()} disabled={data.busy === "save"}>
              {data.busy === "save" ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}保存
            </Button>
          </div>
        }
      />

      {data.error && <FeedbackBanner type="error" message={data.error} />}
      {data.message && <FeedbackBanner type="success" message={data.message} />}
      {!data.settings && <div className="grid min-h-64 place-items-center"><Loader2 className="size-8 animate-spin text-[#007aff]" /></div>}

      {data.settings && (
        <>
          <SettingsTabs active={activeTab} onChange={setActiveTab} />
          {activeTab === "study" && (
            <StudySettingsTab
              settings={data.settings}
              update={data.update}
              ttsState={data.ttsState}
              ttsMessage={data.ttsMessage}
              onTestTts={data.testTts}
              tencentTestState={data.tencentTestState}
              tencentTestMessage={data.tencentTestMessage}
              onTestTencentTranslate={data.testTencentTranslate}
            />
          )}
          {activeTab === "ai" && (
            <AiSettingsTab
              settings={data.settings}
              providerTests={llm.providerTests}
              providerModels={llm.providerModels}
              providerTestModels={llm.providerTestModels}
              onAddProvider={llm.addProvider}
              onUpdateProviderField={llm.updateProviderField}
              onUpdateProviderModels={llm.updateProviderModels}
              onFetchProviderModels={llm.fetchProviderModels}
              onTestProvider={llm.testProvider}
              onProviderTestModelChange={llm.changeProviderTestModel}
              onRemoveProvider={llm.removeProvider}
              onUpdatePurpose={llm.updatePurpose}
            />
          )}
          {activeTab === "data" && (
            <DataSettingsTab
              ecdict={data.ecdict}
              busy={data.busy}
              onEcdictAction={data.ecdictAction}
              onUploadEcdict={data.uploadEcdict}
              onRestore={data.restore}
            />
          )}
        </>
      )}

      {llm.modelPicker && pickerProvider && (
        <ModelPickerDialog
          state={llm.modelPicker}
          provider={pickerProvider}
          filter={llm.modelFilter}
          onFilterChange={llm.setModelFilter}
          onToggle={llm.toggleModel}
          onSelectAll={llm.selectAllModels}
          onClear={() => llm.setModelPicker((current) => current ? { ...current, selected: [] } : current)}
          onApply={llm.applyModelSelection}
          onClose={() => llm.setModelPicker(null)}
        />
      )}
    </div>
  );
}
