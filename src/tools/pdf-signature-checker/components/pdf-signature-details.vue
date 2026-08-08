<script setup lang="ts">
import type { SignatureInfo } from '../pdf-signature-checker.types';

const props = defineProps<{ signature: SignatureInfo }>();
const { signature } = toRefs(props);

const tableHeaders = {
  validityPeriod: 'Validity period',
  issuedBy: 'Issued by',
  issuedTo: 'Issued to',
  pemCertificate: 'PEM certificate',
};

const certs = computed(() => signature.value.meta.certs.map((certificate, index) => ({
  ...certificate,
  validityPeriod: {
    notBefore: new Date(certificate.validityPeriod.notBefore).toLocaleString(),
    notAfter: new Date(certificate.validityPeriod.notAfter).toLocaleString(),
  },
  certificateName: `Certificate ${index + 1}`,
})),
);

type Certificate = SignatureInfo['meta']['certs'][number];

function asValidityPeriod(value: unknown): Certificate['validityPeriod'] {
  return value as Certificate['validityPeriod'];
}

function asIssuedBy(value: unknown): Certificate['issuedBy'] {
  return value as Certificate['issuedBy'];
}

function asIssuedTo(value: unknown): Certificate['issuedTo'] {
  return value as Certificate['issuedTo'];
}

function asPemCertificate(value: unknown): string {
  return value as string;
}
</script>

<template>
  <div flex flex-col gap-2>
    <c-table :data="certs" :headers="tableHeaders">
      <template #validityPeriod="{ value }">
        <c-key-value-list
          :items="[{
            label: 'Not before',
            value: asValidityPeriod(value).notBefore,
          }, {
            label: 'Not after',
            value: asValidityPeriod(value).notAfter,
          }]"
        />
      </template>

      <template #issuedBy="{ value }">
        <c-key-value-list
          :items="[{
            label: 'Common name',
            value: asIssuedBy(value).commonName,
          }, {
            label: 'Organization name',
            value: asIssuedBy(value).organizationName,
          }, {
            label: 'Country name',
            value: asIssuedBy(value).countryName,
          }, {
            label: 'Locality name',
            value: asIssuedBy(value).localityName,
          }, {
            label: 'Organizational unit name',
            value: asIssuedBy(value).organizationalUnitName,
          }, {
            label: 'State or province name',
            value: asIssuedBy(value).stateOrProvinceName,
          }]"
        />
      </template>

      <template #issuedTo="{ value }">
        <c-key-value-list
          :items="[{
            label: 'Common name',
            value: asIssuedTo(value).commonName,
          }, {
            label: 'Organization name',
            value: asIssuedTo(value).organizationName,
          }, {
            label: 'Country name',
            value: asIssuedTo(value).countryName,
          }, {
            label: 'Locality name',
            value: asIssuedTo(value).localityName,
          }, {
            label: 'Organizational unit name',
            value: asIssuedTo(value).organizationalUnitName,
          }, {
            label: 'State or province name',
            value: asIssuedTo(value).stateOrProvinceName,
          }]"
        />
      </template>

      <template #pemCertificate="{ value }">
        <c-modal-value :value="asPemCertificate(value)" label="View PEM cert">
          <template #value>
            <div break-all text-xs>
              {{ asPemCertificate(value) }}
            </div>
          </template>
        </c-modal-value>
      </template>
    </c-table>
  </div>
</template>
