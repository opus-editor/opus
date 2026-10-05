<script lang="ts">
  interface Locale {
    code: string;
    name: string;
  }

  const locales: Locale[] = [
    { code: "en", name: "English" },
    { code: "pt-BR", name: "Português" },
  ];

  let current = $state("en");
</script>

<ul class="locale-list">
  {#each locales as locale (locale.code)}
    <li class:is-active={locale.code === current} onclick={() => (current = locale.code)}>
      {locale.name} <small>({locale.code})</small>
    </li>
  {:else}
    <li>No locales</li>
  {/each}
</ul>

<style>
  .is-active {
    color: #1a5fb4;
    font-weight: 600;
  }
</style>
