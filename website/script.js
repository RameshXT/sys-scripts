document.addEventListener('DOMContentLoaded', () => {
  const copyBtn = document.getElementById('copy-btn');
  const installCmd = document.getElementById('install-cmd');

  if (copyBtn && installCmd) {
    copyBtn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(installCmd.innerText);
        
        copyBtn.textContent = 'COPIED';
        copyBtn.classList.add('copied');
        
        setTimeout(() => {
          copyBtn.textContent = 'COPY';
          copyBtn.classList.remove('copied');
        }, 2000);
      } catch (err) {
        console.error('Failed to copy: ', err);
        copyBtn.textContent = 'ERROR';
      }
    });
  }

  // CLI table copy buttons
  const cliCopyBtns = document.querySelectorAll('.cli-copy');
  cliCopyBtns.forEach(btn => {
    btn.addEventListener('click', async () => {
      const cmd = btn.getAttribute('data-cmd');
      if (!cmd) return;
      try {
        await navigator.clipboard.writeText(cmd);
        
        const originalHtml = btn.innerHTML;
        btn.innerHTML = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>`;
        btn.classList.add('copied');
        
        setTimeout(() => {
          btn.innerHTML = originalHtml;
          btn.classList.remove('copied');
        }, 2000);
      } catch (err) {
        console.error('Failed to copy CLI command: ', err);
      }
    });
  });
});
