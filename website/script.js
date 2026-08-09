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
});
