"use strict";

(() => {
  const input = document.getElementById("trace-input");
  const run = document.getElementById("run");
  const status = document.getElementById("status");
  const file = document.getElementById("trace-file");
  const maximumBytes = 8 * 1024 * 1024;
  const sample = [
    { kind: "config", format: 1, seed: 7, at_ms: 0 },
    { kind: "browse", at_ms: 0, scope: "demo", name: "_http._tcp.local." },
    { kind: "advance", at_ms: 120 },
    { kind: "advance", at_ms: 1200 },
    { kind: "cancel", at_ms: 1300, id: 1 },
    { kind: "close", at_ms: 1400 },
  ].map(value => JSON.stringify(value)).join("\n");

  function message(text, error = false) {
    status.textContent = text;
    status.classList.toggle("error", error);
  }

  function render(id, values, empty) {
    const target = document.getElementById(id);
    target.replaceChildren();
    document.getElementById(`${id === "events" ? "event" : "outbound"}-count`).textContent = String(values.length);
    if (!values.length) {
      const placeholder = document.createElement("p");
      placeholder.className = "empty";
      placeholder.textContent = empty;
      target.appendChild(placeholder);
      return;
    }
    const fragment = document.createDocumentFragment();
    for (const value of values) {
      const detail = document.createElement("details");
      const summary = document.createElement("summary");
      const time = document.createElement("span");
      time.className = "record-time";
      time.textContent = `${value.at_ms ?? 0} ms`;
      const type = document.createElement("span");
      type.className = "record-type";
      type.textContent = value.event;
      summary.append(time, type);
      summary.append(document.createTextNode(value.service?.instance ?? value.scope ?? value.code ?? ""));
      const json = document.createElement("pre");
      json.textContent = JSON.stringify(value, null, 2);
      detail.append(summary, json);
      fragment.appendChild(detail);
    }
    target.appendChild(fragment);
  }

  function clear() {
    render("events", [], "本次回放暂无事件。");
    render("outbound", [], "本次回放暂无待发查询。");
  }

  document.getElementById("sample").addEventListener("click", () => {
    input.value = sample;
    message("已填入查询与取消示例。加载 fixtures/live-20261024.jsonl 可查看真实服务事件。");
  });

  file.addEventListener("change", async () => {
    const selected = file.files[0];
    if (!selected) return;
    try {
      if (selected.size > maximumBytes) throw new Error("文件超过 8 MiB。");
      input.value = new TextDecoder("utf-8", { fatal: true }).decode(await selected.arrayBuffer());
      message(`已加载 ${selected.name}，点击运行开始离线回放。`);
    } catch (error) {
      message(`加载失败：${error.message}`, true);
    }
    file.value = "";
  });

  run.addEventListener("click", () => {
    clear();
    run.disabled = true;
    message("正在离线回放…");
    // Let the status repaint before the synchronous, bounded core callback.
    setTimeout(() => {
      try {
        if (new TextEncoder().encode(input.value).length > maximumBytes) throw new Error("输入超过 8 MiB。");
        const result = JSON.parse(globalThis.moonDiscoverReplay(input.value));
        if (!result.ok) throw new Error(result.line > 0 ? `第 ${result.line} 行：${result.error}` : result.error);
        const events = result.outputs.filter(value => value.event !== "outbound");
        const outbound = result.outputs.filter(value => value.event === "outbound");
        render("events", events, "录制中没有产生事件。");
        render("outbound", outbound, "录制中没有产生待发查询。");
        message(`回放完成 · ${result.frames} 帧 · seed ${result.seed} · ${events.length} 个事件 · ${outbound.length} 个待发查询。查询未发送。`);
      } catch (error) {
        message(`回放失败：${error.message}`, true);
      } finally {
        run.disabled = false;
      }
    }, 0);
  });

  input.value = sample;
  if (typeof globalThis.moonDiscoverReplay === "function") {
    message("MoonBit 核心已就绪。可运行示例，也可粘贴或加载录制文件。");
  } else {
    run.disabled = true;
    message("未找到编译后的 MoonBit 核心。请先运行 scripts/build-replay.ps1，并打开生成目录。", true);
  }
})();
