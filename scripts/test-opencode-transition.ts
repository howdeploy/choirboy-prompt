import { createHash } from "crypto"
import { readFile, rename, writeFile } from "fs/promises"
import { join } from "path"
import { pathToFileURL } from "url"

const [pluginPath, artifactRoot] = process.argv.slice(2)
if (!pluginPath || !artifactRoot) {
  throw new Error("usage: test-opencode-transition.ts PLUGIN ARTIFACT_ROOT")
}

const module = await import(pathToFileURL(pluginPath).href)
const pluginFactory = module.default
if (typeof pluginFactory !== "function") {
  throw new Error("generated OpenCode adapter has no default plugin factory")
}

const hooks = await pluginFactory({} as any)
const onSystem = hooks["experimental.chat.system.transform"]
if (typeof onSystem !== "function") {
  throw new Error("generated OpenCode adapter has no model-bound system hook")
}

const sessionID = "pending-to-ready-fixture"
const systemOutput = (initial: string[] = []) => ({ system: [...initial] })
const choirboyBlock = (output: { system: string[] }) =>
  output.system.find((value) => value.includes(' delivery="session-start"'))

const first = systemOutput([
  '<choirboy-delivery version="fixture" delivery="skill" />\n<choirboy-context>skill fallback</choirboy-context>',
])
await onSystem({ sessionID }, first)
const pending = choirboyBlock(first)
if (!pending?.includes('<choirboy-project-artifacts status="pending"')) {
  throw new Error("first OpenCode model request was not given pending bootstrap")
}
await onSystem({ sessionID }, first)
if (first.system.filter((value) => value.includes(' delivery="session-start"')).length !== 1) {
  throw new Error("OpenCode duplicated memory inside one model-bound context")
}

await rename(
  join(artifactRoot, ".artifact-manifest.saved"),
  join(artifactRoot, ".artifact-manifest.json"),
)

const second = systemOutput()
await onSystem({ sessionID }, second)
const ready = choirboyBlock(second)
if (!ready?.includes("\n# Established project history\n")) {
  throw new Error("ready dossiers were not delivered after pending bootstrap")
}

// A fresh outbound system array represents a later request, including the
// first request after compaction. Exact project memory must be rebuilt there.
const afterCompaction = systemOutput()
await onSystem({ sessionID }, afterCompaction)
if (!choirboyBlock(afterCompaction)?.includes("\n# Established project history\n")) {
  throw new Error("OpenCode compaction evicted exact project memory")
}

await rename(
  join(artifactRoot, ".artifact-manifest.json"),
  join(artifactRoot, ".artifact-manifest.stale"),
)
const fourth = systemOutput()
await onSystem({ sessionID }, fourth)
if (!choirboyBlock(fourth)?.includes('<choirboy-project-artifacts status="pending"')) {
  throw new Error("an older ready delivery hid the current pending lifecycle")
}

await rename(
  join(artifactRoot, ".artifact-manifest.stale"),
  join(artifactRoot, ".artifact-manifest.json"),
)
const request = JSON.parse(
  await readFile(join(artifactRoot, ".artifact-request.json"), "utf8"),
)
const relative = request.projects[0].artifact
const artifactPath = join(artifactRoot, relative)
const freshnessCanary = "OpenCode freshness canary from updated project history."
const document = `${await readFile(artifactPath, "utf8")}\n${freshnessCanary}\n`
await writeFile(artifactPath, document, "utf8")
const manifestPath = join(artifactRoot, ".artifact-manifest.json")
const manifest = JSON.parse(await readFile(manifestPath, "utf8"))
const record = Object.values(manifest.projects as Record<string, any>).find(
  (value: any) => value.path === relative,
) as any
if (!record) throw new Error("fixture manifest has no first project record")
record.artifact_sha256 = createHash("sha256").update(document).digest("hex")
await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8")

const refreshed = systemOutput()
await onSystem({ sessionID }, refreshed)
if (!choirboyBlock(refreshed)?.includes(freshnessCanary)) {
  throw new Error("an older ready delivery hid refreshed project history")
}
