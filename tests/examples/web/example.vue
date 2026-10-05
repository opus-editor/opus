<script setup lang="ts">
import { ref } from "vue";

interface Locale {
  code: string;
  name: string;
}

const locales: Locale[] = [
  { code: "en", name: "English" },
  { code: "pt-BR", name: "Português" },
];

const current = ref("en");
</script>

<template>
  <ul class="locale-list">
    <li
      v-for="locale in locales"
      :key="locale.code"
      :class="{ locale: true, 'is-active': locale.code === current }"
      @click="current = locale.code"
    >
      {{ locale.name }} <small>({{ locale.code }})</small>
    </li>
  </ul>
</template>

<style scoped>
.locale.is-active {
  color: #1a5fb4;
  font-weight: 600;
}
</style>
