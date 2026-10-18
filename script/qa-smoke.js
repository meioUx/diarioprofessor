// Verifica autenticação e páginas de consulta com os usuários fictícios da carga QA.
const { request } = require('@playwright/test');

async function main() {
  const baseURL = process.env.QA_BASE_URL || 'http://localhost:3000';
  const year = process.env.QA_YEAR || new Date().getFullYear();
  for (const role of ['professor', 'gestor']) {
    const context = await request.newContext({ baseURL, timeout: 120000 });
    try {
      const login = await context.get('/');
      const html = await login.text();
      const token = html.match(/name="authenticity_token"[^>]*value="([^"]+)"/);
      const action = html.match(/<form[^>]*action="([^"]+)"/);
      if (!token || !action) throw new Error('Formulário de login não encontrado');
      const response = await context.post(action[1], { form: {
        authenticity_token: token[1], 'user[credentials]': `qa.${role}.${year}`,
        'user[password]': process.env.QA_PASSWORD || 'QaTeste2026!'
      } });
      const dashboard = await response.text();
      if (response.status() !== 200 || !dashboard.includes('id="left-panel"') ||
          dashboard.includes('id="user_credentials"')) throw new Error(`Login falhou: ${role}`);
      console.log(`${role}: login e painel OK`);
      const links = [...dashboard.matchAll(/href="(\/[^"?#]+)"/g)].map(match => match[1]);
      const pages = [...new Set(links)].filter(path =>
        /planos|avaliacoes|frequencias|calendarios|observacoes|justificativas|educacionais|turmas|alunos|professores|usuarios$/.test(path) &&
        !/sair|excluir|sincroniza|envio|novo|nova/.test(path));
      for (const path of pages) {
        const page = await context.get(path);
        const body = await page.text();
        if (page.status() >= 400 || body.includes('id="user_credentials"')) {
          throw new Error(`${role}: ${path} respondeu ${page.status()}`);
        }
        console.log(`${role}: ${path} ${page.status()}`);
      }
    } finally {
      await context.dispose();
    }
  }
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
