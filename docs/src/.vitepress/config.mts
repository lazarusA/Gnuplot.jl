import { defineConfig } from 'vitepress'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import mathjax3 from "markdown-it-mathjax3";
import footnote from "markdown-it-footnote";
import { OramaPlugin } from '@orama/plugin-vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  base: '/Gnuplot.jl/',// TODO: replace this in makedocs!
  title: 'Gnuplot.jl',
  description: "A VitePress Site",
  lastUpdated: true,
  cleanUrls: true,
  outDir: '../final_site', // This is required for MarkdownVitepress to work correctly...
  
  ignoreDeadLinks: true,

  markdown: {
    math: true,
    config(md) {
      md.use(tabsMarkdownPlugin),
      md.use(mathjax3),
      md.use(footnote)
    },
    theme: {
      light: "github-light",
      dark: "github-dark"}
  },
  extends: {
    vite: {
      plugins: [OramaPlugin()],
    },
  },
  themeConfig: {
    outline: 'deep',
    logo: { src: '/logo.png', width: 24, height: 24},
    nav: [
{ text: 'Home', link: '/index' },
{ text: 'Installation', link: '/install' },
{ text: 'Basic usage', link: '/basic' },
{ text: 'Style guide', link: '/style' },
{ text: 'Examples', link: '/examples' },
{ text: 'Advanced usage', collapsed: false, items: [
{ text: 'Advanced', link: '/advanced' },
{ text: 'Plot recipes', link: '/recipes' },
{ text: 'Gnuplot terminals', link: '/terminals' },
{ text: 'Package options', link: '/options' }]
 },
{ text: 'API', link: '/api' }
]
,
    sidebar: [
{ text: 'Home', link: '/index' },
{ text: 'Installation', link: '/install' },
{ text: 'Basic usage', link: '/basic' },
{ text: 'Style guide', link: '/style' },
{ text: 'Examples', link: '/examples' },
{ text: 'Advanced usage', collapsed: false, items: [
{ text: 'Advanced', link: '/advanced' },
{ text: 'Plot recipes', link: '/recipes' },
{ text: 'Gnuplot terminals', link: '/terminals' },
{ text: 'Package options', link: '/options' }]
 },
{ text: 'API', link: '/api' }
]
,
    editLink: { pattern: "https://https://github.com/gcalderone/Gnuplot.jl/edit/master/docs/src/:path" },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/gcalderone/Gnuplot.jl' }
    ],
    footer: {
      message: 'Made with <a href="https://luxdl.github.io/DocumenterVitepress.jl/dev/" target="_blank"><strong>DocumenterVitepress.jl</strong></a><br>',
      copyright: `© Copyright ${new Date().getUTCFullYear()}.`
    }
  }
})
