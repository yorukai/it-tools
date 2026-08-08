<script setup lang="ts">
import { useStorage } from '@vueuse/core';
import composerize from 'composerize';
import { parse, stringify } from 'yaml';
import { useDownloadFileFromBase64 } from '@/composable/downloadBase64';
import { textToBase64 } from '@/utils/base64';
import TextareaCopyable from '@/components/TextareaCopyable.vue';

type ComposeVersion = 'v2x' | 'v3x' | 'latest';
interface ComposeService { labels?: string[] | Record<string, string>; [key: string]: unknown }
interface ComposeData {
  name?: string
  services?: Record<string, ComposeService>
  [key: string]: unknown
}

const composeVersionOptions = [
  { label: 'V2 - 2.X', value: 'v2x' },
  { label: 'V3 - V3.X', value: 'v3x' },
  { label: 'CommonSpec', value: 'latest' },
] as const;
const indentationOptions = [2, 4, 8].map(value => ({ label: `${value}`, value }));
const collapseSectionTitle = 'Merge with existing docker compose file';

const dockerRun = useStorage(
  'docker-run-to-docker-compose-converter:docker-run',
  'docker run -p 80:80 -v /var/run/docker.sock:/tmp/docker.sock:ro --restart always --log-opt max-size=1g nginx',
);
const version = useStorage<ComposeVersion>('docker-run-to-docker-compose-converter:version', 'latest');
const indentation = useStorage<number>('docker-run-to-docker-compose-converter:indentation', 2);
const name = useStorage('docker-run-to-docker-compose-converter:name', '');
const traefikDomain = useStorage('docker-run-to-docker-compose-converter:traefik-domain', '');
const traefikNetwork = useStorage('docker-run-to-docker-compose-converter:traefik-network', 'traefik_web');
const traefikPort = useStorage('docker-run-to-docker-compose-converter:traefik-port', '');
const watchtowerEnabled = useStorage('docker-run-to-docker-compose-converter:watchtower-enabled', false);
const existingComposeFile = useStorage('docker-run-to-docker-compose-converter:existing-compose-file', '');

function normalizeServiceName(name: string): string {
  return name.replace(/[^a-zA-Z0-9-]/g, '-').toLowerCase();
}

function extractPort(entry: unknown): string | undefined {
  if (typeof entry === 'number') {
    return String(entry);
  }

  if (typeof entry === 'string') {
    const valueWithoutProtocol = entry.split('/')[0];
    return valueWithoutProtocol.split(':').at(-1);
  }

  if (typeof entry === 'object' && entry !== null && 'target' in entry) {
    const target = (entry as { target?: string | number }).target;
    if (typeof target === 'number') {
      return String(target);
    }

    return typeof target === 'string' ? target : undefined;
  }

  return undefined;
}

function getDockerRunServiceNames(composeData: ComposeData): string[] {
  return composeData.services ? Object.keys(composeData.services) : [];
}

function extractSingleServicePort(composeData: ComposeData, serviceNames: string[]): string | undefined {
  const services = composeData.services;
  if (!services) {
    return undefined;
  }

  const discoveredPorts = serviceNames.flatMap((serviceName) => {
    const service = services[serviceName];
    if (!service || !Array.isArray(service.ports)) {
      return [];
    }

    return service.ports.map(extractPort).filter((port): port is string => port !== undefined);
  });

  return discoveredPorts.length === 1 ? discoveredPorts[0] : undefined;
}

const conversionBaseResult = computed(() => {
  try {
    const yaml = composerize(
      dockerRun.value.trim(),
      existingComposeFile.value.trim() || undefined,
      version.value,
      indentation.value,
    );

    return { yaml, error: '' };
  }
  catch (error) {
    return { yaml: '', error: error instanceof Error ? error.message : String(error) };
  }
});

const dockerRunOnlyResult = computed(() => {
  try {
    const yaml = composerize(
      dockerRun.value.trim(),
      undefined,
      version.value,
      indentation.value,
    );

    return { yaml, error: '' };
  }
  catch (error) {
    return { yaml: '', error: error instanceof Error ? error.message : String(error) };
  }
});

const dockerRunServiceNames = computed(() => {
  if (dockerRunOnlyResult.value.yaml === '') {
    return [] as string[];
  }

  const composeData = (parse(dockerRunOnlyResult.value.yaml) ?? {}) as ComposeData;
  return getDockerRunServiceNames(composeData);
});

const singleServicePort = computed(() => {
  if (dockerRunOnlyResult.value.yaml === '') {
    return undefined;
  }

  const composeData = (parse(dockerRunOnlyResult.value.yaml) ?? {}) as ComposeData;
  return extractSingleServicePort(composeData, dockerRunServiceNames.value);
});

const automaticTraefikPortPlaceholder = computed(() => singleServicePort.value ?? '80');

const effectiveTraefikPort = computed(() => {
  const configuredPort = traefikPort.value.trim();
  return configuredPort !== '' ? configuredPort : automaticTraefikPortPlaceholder.value;
});

function addServiceLabels(composeData: ComposeData): ComposeData {
  const hasTraefikConfig = traefikDomain.value.trim() !== '';
  if (!hasTraefikConfig && !watchtowerEnabled.value) {
    return composeData;
  }

  const services = composeData.services;
  if (!services || dockerRunServiceNames.value.length === 0) {
    return composeData;
  }

  for (const serviceName of dockerRunServiceNames.value) {
    if (!services[serviceName]) {
      continue;
    }

    const service = services[serviceName] ?? {};
    const normalizedServiceName = normalizeServiceName(serviceName);
    const labelsToAdd: Record<string, string> = {};

    if (hasTraefikConfig) {
      labelsToAdd['traefik.enable'] = 'true';
      labelsToAdd[`traefik.http.routers.${normalizedServiceName}.rule`] = `Host(\`${traefikDomain.value.trim()}\`)`;
      labelsToAdd[`traefik.http.services.${normalizedServiceName}.loadbalancer.server.port`] = effectiveTraefikPort.value;
      labelsToAdd['traefik.docker.network'] = traefikNetwork.value.trim() || 'traefik_web';
    }

    if (watchtowerEnabled.value) {
      labelsToAdd['com.centurylinklabs.watchtower.enable'] = 'true';
    }

    if (Array.isArray(service.labels)) {
      const removedUpdatedKeys = service.labels.filter((entry) => {
        const key = entry.split('=')[0];
        return !Object.keys(labelsToAdd).includes(key);
      });

      service.labels = [
        ...removedUpdatedKeys,
        ...Object.entries(labelsToAdd).map(([key, value]) => `${key}=${value}`),
      ];
    }
    else {
      const existingLabels = service.labels && typeof service.labels === 'object' ? service.labels : {};
      service.labels = { ...existingLabels, ...labelsToAdd };
    }

    services[serviceName] = service;
  }

  composeData.services = services;
  return composeData;
}

function enrichComposeYaml(rawYaml: string): string {
  const composeData = (parse(rawYaml) ?? {}) as ComposeData;

  if (version.value === 'latest' && name.value.trim() !== '') {
    composeData.name = name.value.trim();
  }

  const composeWithServiceLabels = addServiceLabels(composeData);
  return stringify(composeWithServiceLabels, { indent: indentation.value });
}

const conversionResult = computed(() => {
  if (conversionBaseResult.value.error !== '') {
    return { yaml: '', error: conversionBaseResult.value.error };
  }

  return { yaml: enrichComposeYaml(conversionBaseResult.value.yaml), error: '' };
});
const dockerCompose = computed(() => conversionResult.value.yaml);
const dockerComposeBase64 = computed(() => `data:application/yaml;base64,${textToBase64(dockerCompose.value)}`);
const { download } = useDownloadFileFromBase64({ source: dockerComposeBase64, filename: 'docker-compose.yml' });
</script>

<template>
  <div>
    <div style="margin: 0 auto; max-width: 900px" mb-5 flex flex-wrap justify-center gap-2>
      <c-select v-model:value="version" label="Version" style="min-width: 180px" :options="composeVersionOptions" />
      <c-select v-model:value="indentation" label="Indentation" style="min-width: 140px" :options="indentationOptions" />
      <n-form-item label="Watchtower" :show-feedback="false">
        <n-switch v-model:value="watchtowerEnabled" />
      </n-form-item>
      <c-input-text
        v-if="version === 'latest'"
        v-model:value="name"
        label="Name"
        style="min-width: 180px"
        placeholder="compose project name"
      />
      <c-input-text
        v-model:value="traefikDomain"
        label="Traefik domain"
        style="min-width: 220px"
        placeholder="example.com"
      />
      <c-input-text
        v-model:value="traefikPort"
        label="Traefik port"
        style="min-width: 150px"
        :placeholder="automaticTraefikPortPlaceholder"
      />
      <c-input-text
        v-model:value="traefikNetwork"
        label="Traefik network"
        style="min-width: 180px"
        placeholder="traefik_web"
      />
    </div>

    <details style="max-width: 900px; margin: 0 auto 20px auto;">
      <summary style="cursor: pointer">
        {{ collapseSectionTitle }}
      </summary>
      <div style="margin-top: 8px">
        <c-input-text
          v-model:value="existingComposeFile"
          label="Existing compose file"
          style="font-family: monospace"

          raw-text multiline monospace
          placeholder="Paste existing compose.yaml / docker-compose.yml here..."
          rows="6"
        />
      </div>
    </details>

    <c-input-text
      v-model:value="dockerRun"
      label="Your docker run command:"
      style="font-family: monospace"
      multiline
      raw-text
      monospace
      placeholder="Your docker run command to convert..."
      rows="3"
    />

    <n-divider />

    <TextareaCopyable :value="dockerCompose" language="yaml" />

    <div mt-5 flex justify-center>
      <c-button :disabled="dockerCompose === ''" secondary @click="download">
        Download docker-compose.yml
      </c-button>
    </div>

    <n-alert v-if="conversionResult.error" mt-5 title="The following errors occurred" type="error">
      {{ conversionResult.error }}
    </n-alert>
  </div>
</template>
