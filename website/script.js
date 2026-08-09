document.addEventListener('DOMContentLoaded', () => {
  // 1. Typing Animation for Terminal
  const cmdElement = document.getElementById('install-cmd');
  const fullCmd = 'irm https://github.com/RameshXT/hotkeys/releases/latest/download/xtkeys.ps1 | iex';
  let i = 0;
  
  function typeWriter() {
    if (i < fullCmd.length) {
      cmdElement.textContent += fullCmd.charAt(i);
      i++;
      // Randomize typing speed for realism
      const speed = Math.random() * 30 + 10;
      setTimeout(typeWriter, speed);
    }
  }
  
  // Start typing after a short delay
  setTimeout(typeWriter, 500);

  // 2. Copy to Clipboard
  const copyBtn = document.getElementById('copy-btn');
  if (copyBtn) {
    copyBtn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(fullCmd);
        
        copyBtn.textContent = 'COPIED!';
        copyBtn.classList.add('copied');
        
        setTimeout(() => {
          copyBtn.textContent = 'COPY';
          copyBtn.classList.remove('copied');
        }, 2000);
      } catch (err) {
        console.error('Failed to copy: ', err);
        copyBtn.textContent = 'FAILED';
      }
    });
  }

  // 3. 3D Tilt Effect on Hover (Bento Cards)
  const cards = document.querySelectorAll('.tilt-card');
  
  cards.forEach(card => {
    card.addEventListener('mousemove', (e) => {
      const rect = card.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      
      const centerX = rect.width / 2;
      const centerY = rect.height / 2;
      
      // Calculate rotation (max 5 degrees)
      const rotateX = ((y - centerY) / centerY) * -5;
      const rotateY = ((x - centerX) / centerX) * 5;
      
      card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale3d(1.02, 1.02, 1.02)`;
    });
    
    card.addEventListener('mouseleave', () => {
      card.style.transform = `perspective(1000px) rotateX(0deg) rotateY(0deg) scale3d(1, 1, 1)`;
      card.style.transition = 'transform 0.5s ease';
    });
    
    card.addEventListener('mouseenter', () => {
      card.style.transition = 'transform 0.1s ease';
    });
  });
});
