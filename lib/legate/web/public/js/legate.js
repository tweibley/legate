// Legate web UI — framework JavaScript.
// Extracted from layout.slim. No server-side interpolation lives here;
// keep page-specific values in the views and call into these helpers.

// Add the CSRF token to every htmx request.
document.addEventListener('htmx:configRequest', function (e) {
  var t = document.querySelector('meta[name="csrf-token"]');
  if (t) e.detail.headers['X-CSRF-Token'] = t.content;
});

// Mirror the same for raw fetch(): inject the token on same-origin
// mutating requests so individual call sites don't each have to remember
// it (and can't silently 403 when they forget).
(function () {
  var nativeFetch = window.fetch;
  if (!nativeFetch) return;
  var SAFE = { GET: true, HEAD: true, OPTIONS: true };
  window.fetch = function (resource, init) {
    init = init || {};
    var method = (init.method || (resource && resource.method) || 'GET').toUpperCase();
    var url = (typeof resource === 'string') ? resource : ((resource && resource.url) || '');
    var sameOrigin = (url.charAt(0) === '/' && url.charAt(1) !== '/') ||
      url === window.location.origin || url.indexOf(window.location.origin + '/') === 0;
    if (!SAFE[method] && sameOrigin) {
      var meta = document.querySelector('meta[name="csrf-token"]');
      if (meta) {
        var headers = new Headers(init.headers || (typeof resource !== 'string' && resource.headers) || undefined);
        if (!headers.has('X-CSRF-Token')) headers.set('X-CSRF-Token', meta.content);
        init.headers = headers;
      }
    }
    return nativeFetch.call(this, resource, init);
  };
})();

// Escape interpolated values before they go into an innerHTML sink.
window.escapeHtml = function (value) {
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
};

// Global keyboard shortcut: Cmd/Ctrl+K to focus search
document.addEventListener('keydown', function(e) {
  if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
    e.preventDefault();
    const searchInput = document.querySelector('#agent-search-input, .search-input, input[type="search"]');
    if (searchInput) {
      searchInput.focus();
      searchInput.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }
});

// Theme toggle function (global)
function toggleTheme() {
  const current = document.documentElement.getAttribute('data-theme');
  const next = current === 'dark' ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', next);
  localStorage.setItem('legate-theme', next);
  // Update icon
  const icon = document.querySelector('.theme-toggle i');
  if (icon) {
    icon.className = next === 'dark' ? 'fas fa-sun' : 'fas fa-moon';
  }
  // Update highlight.js theme
  updateHljsTheme(next);
}

// Update highlight.js stylesheet based on theme
function updateHljsTheme(theme) {
  const lightSheet = document.querySelector('link[data-hljs-theme="light"]');
  const darkSheet = document.querySelector('link[data-hljs-theme="dark"]');
  if (lightSheet && darkSheet) {
    if (theme === 'dark') {
      lightSheet.media = 'not all';
      darkSheet.media = 'all';
    } else {
      lightSheet.media = 'all';
      darkSheet.media = 'not all';
    }
  }
}

// Update theme toggle icon and highlight.js theme on load
document.addEventListener('DOMContentLoaded', () => {
  const theme = document.documentElement.getAttribute('data-theme');
  const icon = document.querySelector('.theme-toggle i');
  if (icon) {
    icon.className = theme === 'dark' ? 'fas fa-sun' : 'fas fa-moon';
  }
  // Set highlight.js theme based on saved theme preference
  if (typeof updateHljsTheme === 'function') {
    updateHljsTheme(theme);
  }
});

document.addEventListener('DOMContentLoaded', () => {
  // Navbar burger toggle
  const $navbarBurgers = Array.prototype.slice.call(document.querySelectorAll('.navbar-burger'), 0);
  if ($navbarBurgers.length > 0) {
    $navbarBurgers.forEach( el => {
      el.addEventListener('click', () => {
        const target = el.dataset.target;
        const $target = document.getElementById(target);
        el.classList.toggle('is-active');
        $target.classList.toggle('is-active');
      });
    });
  }

  // CodeMirror global instances and observers
  window.codeMirrorInstances = window.codeMirrorInstances || {};
  window.codeMirrorObservers = window.codeMirrorObservers || {};

  // Initialize CodeMirror editors
  function initCodeMirrorEditor(editorElement, options = {}) {
    if (editorElement && editorElement.id && !window.codeMirrorInstances[editorElement.id]) {
      const elementId = editorElement.id;
      try {
        const defaultOptions = {
          lineNumbers: true,
          mode: { name: "javascript", json: true },
          theme: "default",
          lineWrapping: true,
          gutters: ["CodeMirror-lint-markers"],
          lint: false, // Default to false, enable for JSON
          extraKeys: {"Ctrl-Q": function(cm){ cm.foldCode(cm.getCursor()); }, "Ctrl-Space": "autocomplete"},
          foldGutter: true,
          gutters: ["CodeMirror-linenumbers", "CodeMirror-foldgutter", "CodeMirror-lint-markers"]
        };

        if (options.mode === 'text/plain' || elementId.includes('instruction')) {
          options.mode = 'text/plain';
          options.lint = false; // No linting for plain text
        } else if (options.mode === 'markdown' || elementId.includes('some-markdown-field')) { // Example for markdown
          options.mode = 'markdown';
          options.lint = false;
        } else { // Default to JSON mode
          options.mode = { name: "javascript", json: true };
          options.lint = true; // Enable linting for JSON
        }

        const cmOptions = Object.assign({}, defaultOptions, options);
        const instance = CodeMirror.fromTextArea(editorElement, cmOptions);

        instance.on('change', function(cm) {
          cm.save(); // Update original textarea on change
        });

        window.codeMirrorInstances[elementId] = instance;
        // Refresh after a slight delay to ensure layout is complete
        setTimeout(() => instance.refresh(), 50);

        // Observer to refresh CodeMirror when it becomes visible
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                   if(window.codeMirrorInstances[elementId]) {
                      setTimeout(() => window.codeMirrorInstances[elementId].refresh(), 50);
                   }
                }
            });
        }, { threshold: 0.1 });
        observer.observe(instance.getWrapperElement());
        window.codeMirrorObservers[elementId] = observer;

      } catch (e) {
        // Fallback if CodeMirror fails to initialize
        editorElement.style.display = 'block';
        console.error("CodeMirror initialization error for ID " + elementId + ":", e);
      }
    } else if (editorElement && editorElement.id && window.codeMirrorInstances[editorElement.id]) {
      // If instance exists, just refresh it (e.g., after HTMX swap)
      const elementId = editorElement.id;
      setTimeout(() => {
         if (window.codeMirrorInstances[elementId]) {
            window.codeMirrorInstances[elementId].refresh()
         }
        }, 50);
    }
  }

  // Destroy CodeMirror instance
  function destroyCodeMirrorInstance(elementId) {
    if (window.codeMirrorObservers && window.codeMirrorObservers[elementId]) {
      window.codeMirrorObservers[elementId].disconnect();
      delete window.codeMirrorObservers[elementId];
    }

    if (window.codeMirrorInstances && window.codeMirrorInstances[elementId]) {
      const instance = window.codeMirrorInstances[elementId];
      const wrapper = instance.getWrapperElement();
      try {
        instance.toTextArea(); // Restore original textarea
      } catch (e) {
        // console.error("Error converting CodeMirror to TextArea for ID " + elementId + ":", e);
      }
      delete window.codeMirrorInstances[elementId];
    }
  }

  // Initialize CodeMirror for relevant textareas on the page or within a target element
  function initializeRelevantEditors(targetElement = document.body) {
    const editorsToInit = [
      { id: 'mcp_servers_json', options: {} },
      { id: 'instruction', options: { mode: 'text/plain'} },
      { id: 'mcp-json-editor', options: {} },
      { id: 'mcp-json-display', options: { readOnly: true } },
      { id: 'task-json-editor', options: {} },
      { id: 'direct-task-json-input', options: {} },
      { id: 'edit-instruction-textarea', options: { mode: 'text/plain'} }
    ];

    editorsToInit.forEach(editor => {
      let element = null;
      if (targetElement && targetElement !== document.body && typeof targetElement.querySelector === 'function') {
         element = targetElement.querySelector(`#${editor.id}`);
      }
      if (!element) {
        element = document.getElementById(editor.id);
      }
      if (element) {
         initCodeMirrorEditor(element, editor.options);
      }
    });
  }

  // Highlight.js initialization
  function initializeHighlighting(targetElement = document.body) {
    const selector = targetElement === document.body ? 'pre code:not(.language-mermaid):not(.mermaid)' : 'pre code:not(.language-mermaid):not(.mermaid)';
    targetElement.querySelectorAll(selector).forEach(function(block) {
      if (!block.classList.contains('hljs')) {
         try {
           hljs.highlightElement(block);
         } catch (e) {
           console.error("Highlight.js error:", e, "on block:", block);
         }
      }
    });
  }

  // Mermaid.js preparation
  function prepareMermaidContainers(targetElement = document.body) {
    const selector = targetElement === document.body ? 'code.language-mermaid' : 'code.language-mermaid';
    targetElement.querySelectorAll(selector).forEach(block => {
      const preElement = block.closest('pre');
      if (!preElement || preElement.dataset.mermaidProcessed === 'true') {
        return;
      }
      const diagramCode = block.textContent || block.innerText;
      if (!diagramCode || diagramCode.trim() === '') {
        return;
      }
      const mermaidContainer = document.createElement('div');
      mermaidContainer.className = 'mermaid';
      mermaidContainer.textContent = diagramCode;
      if (preElement.parentNode) {
        preElement.parentNode.replaceChild(mermaidContainer, preElement);
        mermaidContainer.dataset.mermaidProcessed = 'true';
      }
    });
  }

  // Initial calls on DOMContentLoaded
  initializeRelevantEditors(document.body);
  initializeHighlighting(document.body);
  prepareMermaidContainers(document.body);
  try {
    const initialMermaidNodes = document.querySelectorAll('.mermaid:not(#mermaid-modal-content .mermaid)');
    if (initialMermaidNodes.length > 0) {
      mermaid.run({ nodes: Array.from(initialMermaidNodes) });
    }
  } catch (e) {
    console.error("Error running mermaid.run() on initial load (non-modal):", e);
  }

  // Health Check Logic
  if (!window.healthCheckInitialized) {
    const healthCheckModal = document.getElementById('health-check-modal');
    let isServerUnavailable = false;
    let healthCheckIntervalId = null;

    window.checkServerHealth = function() {
      fetch('/healthz', { method: 'GET', cache: 'no-cache' })
        .then(response => {
          if (!response.ok) {
            throw new Error(`Server status: ${response.status}`);
          }
          if (isServerUnavailable) {
            // Server was down but is now back up
            // Reload the page to get fresh agent statuses
            // (Agent statuses are reset to 'stopped' on server restart)
            if (healthCheckModal) healthCheckModal.classList.remove('is-active');
            isServerUnavailable = false;
            showToast("Server connection restored. Refreshing...", "is-success");
            // Short delay to show the toast, then reload
            setTimeout(() => {
              window.location.reload();
            }, 500);
          }
        })
        .catch(error => {
          if (!isServerUnavailable) {
            if (healthCheckModal) healthCheckModal.classList.add('is-active');
            isServerUnavailable = true;
          }
        });
    }
    if (typeof window.checkServerHealth === 'function') {
      window.checkServerHealth();
      healthCheckIntervalId = setInterval(window.checkServerHealth, 5000);
    }
    window.healthCheckInitialized = true;
  }

  // --- Mermaid Modal Handling Setup ---
  function setupMermaidModal() {
    const modal = document.getElementById('mermaid-modal');
    const modalContentArea = document.getElementById('mermaid-modal-content');
    const closeButtons = modal.querySelectorAll('.modal-close-button, .modal-background');

    if (!modal || !modalContentArea) {
      console.error("Mermaid modal main elements not found for setup.");
      return;
    }

    function closeModal() {
      modal.classList.remove('is-active');
      document.documentElement.classList.remove('is-clipped');
      modalContentArea.innerHTML = ''; // Clear content when modal closes
    }

    closeButtons.forEach(button => {
      button.addEventListener('click', closeModal);
    });

    // Listen for clicks on the body to catch .show-mermaid-flow-btn
    document.body.addEventListener('click', function(event) {
      const triggerButton = event.target.closest('.show-mermaid-flow-btn');
      if (triggerButton) {
        event.preventDefault();
        const mermaidDefinition = triggerButton.dataset.mermaidDefinition;

        if (mermaidDefinition && mermaidDefinition.trim() !== '') {
          modalContentArea.innerHTML = ''; // Clear previous
          const mermaidTargetPre = document.createElement('pre');
          mermaidTargetPre.className = 'mermaid';
          mermaidTargetPre.textContent = mermaidDefinition;
          modalContentArea.appendChild(mermaidTargetPre);

          modal.classList.add('is-active');
          document.documentElement.classList.add('is-clipped');

          // Delay rendering slightly to ensure modal is visible and DOM updated
          setTimeout(() => {
            try {
               mermaid.run({ nodes: [mermaidTargetPre] });
             } catch (e) {
               console.error("Error rendering Mermaid in modal:", e);
               mermaidTargetPre.textContent = `Error rendering diagram:\n${e.message}\n\n${mermaidDefinition}`;
             }
          }, 50);
        } else {
          console.warn("Mermaid definition data attribute was missing or empty on button:", triggerButton);
          showToast("Could not load execution flow diagram.", "is-warning");
        }
      }
    });
  }
  setupMermaidModal();
  // --- END Mermaid Modal Handling ---
}); // End DOMContentLoaded

// HTMX Event Listener for afterSwap
document.body.addEventListener('htmx:afterSwap', function(event) {
  const targetElement = event.detail.target;
  const newElement = event.detail.elt;
  let elementToScan = newElement || targetElement;

  if (elementToScan) {
    if (typeof initializeRelevantEditors === 'function') initializeRelevantEditors(elementToScan);
    if (typeof initializeHighlighting === 'function') initializeHighlighting(elementToScan);
    if (typeof prepareMermaidContainers === 'function') prepareMermaidContainers(elementToScan);
    try {
       const mermaidNodesInSwap = elementToScan.querySelectorAll ? elementToScan.querySelectorAll('.mermaid:not(#mermaid-modal-content .mermaid)') : [];
       if (mermaidNodesInSwap.length > 0) {
          mermaid.run({ nodes: mermaidNodesInSwap });
       }
    } catch (e) {
       console.error("Error running mermaid.run() after htmx swap on specific nodes:", e);
    }
  } else {
     if (typeof initializeHighlighting === 'function') initializeHighlighting(document.body);
     if (typeof prepareMermaidContainers === 'function') prepareMermaidContainers(document.body);
     try {
        const nonModalMermaidNodes = document.querySelectorAll('.mermaid:not(#mermaid-modal-content .mermaid)');
        if (nonModalMermaidNodes.length > 0) {
           mermaid.run({ nodes: Array.from(nonModalMermaidNodes) });
        }
     } catch (e) {
        console.error("Error running mermaid.run() after htmx swap (fallback global):", e);
     }
  }

  const triggerHeader = event.detail.xhr.getResponseHeader('HX-Trigger-After-Swap');
  if (triggerHeader) {
    try {
      if (triggerHeader.startsWith('{') && triggerHeader.endsWith('}')) {
         const triggers = JSON.parse(triggerHeader);
         if (triggers.showToast && typeof showToast === 'function') {
             showToast(triggers.showToast.message, triggers.showToast.type);
         }
      } else {
        triggerHeader.split(',').forEach(triggerName => {
          triggerName = triggerName.trim();
          if (typeof showToast === 'function') {
            if (triggerName === 'showRestartToast') {
              showToast("Agent automatically restarted to apply changes.", "is-info");
            } else if (triggerName === 'showRestartErrorToast') {
              showToast("Error: Failed to automatically restart agent. Please stop/start manually.", "is-danger");
            } else if (triggerName === 'showSaveSuccessToast') {
              showToast("Configuration saved successfully.", "is-success");
            }
          }
        });
      }
    } catch (e) {
       if (triggerHeader === 'showRestartToast' && typeof showToast === 'function') showToast("Agent automatically restarted.", "is-info");
    }
  }
});

// HTMX Event Listener for beforeSwap
document.body.addEventListener('htmx:beforeSwap', function(event) {
    const swapTarget = event.detail.target;
    if (swapTarget && swapTarget.id === 'agent-mcp-display-container') {
        const editorId = 'mcp-json-editor';
        if (typeof destroyCodeMirrorInstance === 'function') destroyCodeMirrorInstance(editorId);
    }
    if (swapTarget && swapTarget.id === 'agent-instruction-display-container') {
        const editorId = 'edit-instruction-textarea';
        if (typeof destroyCodeMirrorInstance === 'function') destroyCodeMirrorInstance(editorId);
    }
});

// HTMX Event Listener for afterRequest
document.body.addEventListener('htmx:afterRequest', function(event) {
  const config = event.detail.requestConfig;
  const xhr = event.detail.xhr;
  const elt = config.elt;

  if (elt && elt.id === 'generate-example-task-btn') {
     const editorId = 'direct-task-json-input';
     const editorInstance = window.codeMirrorInstances[editorId];
     if (!editorInstance) {
         if (typeof showToast === 'function') showToast("Task editor is not ready. Please wait.", "is-warning");
         return;
     }
     if (event.detail.successful) {
       try {
         const responseJson = xhr.responseText;
         editorInstance.setValue(responseJson);
         if (typeof showToast === 'function') showToast("Example task generated.", "is-info", 2000);
       } catch (e) {
         if (typeof showToast === 'function') showToast("Failed to update task editor with example.", "is-danger");
       }
     } else {
       if (typeof showToast === 'function') showToast(`Failed to generate example (Status: ${xhr.status})`, "is-danger");
     }
   }

   const triggerHeader = xhr.getResponseHeader('HX-Trigger-After-Swap');
   if (config.path && config.path.includes('/execute') && triggerHeader && triggerHeader.startsWith('showTaskError')) {
       try {
           const responseJson = xhr.responseText;
           const parsedResponse = JSON.parse(responseJson);
           const errorMessage = parsedResponse?.error || parsedResponse?.message || "An unknown execution error occurred.";
           const errorHtml =
             `<div class="notification is-danger is-light mt-3 is-small">
                <button class="delete" type="button" onclick="this.parentElement.remove();"></button>
                <strong>Execution Error:</strong><br>
                <pre style="white-space: pre-wrap; word-break: break-all;">${escapeHtml(errorMessage)}</pre>
              </div>`;
           const targetElement = document.getElementById('task-result');
           if (targetElement) {
               targetElement.innerHTML = errorHtml;
           }
       } catch (e) {
           const targetElement = document.getElementById('task-result');
           if (targetElement) {
               targetElement.innerHTML = '<div class="notification is-danger is-light mt-3 is-small">Failed to parse error response from server.</div>';
           }
       }
   }
});

// Function to show toast notifications
function showToast(message, type = 'is-info', duration = 4000) {
    const toastContainer = document.getElementById('toast-container');
    if (!toastContainer) {
        return;
    }
    const toast = document.createElement('div');
    toast.className = `notification ${type} is-light`;
    toast.style.marginBottom = '0.5em';
    toast.style.opacity = '0';
    toast.style.transition = 'opacity 0.3s ease-in-out';
    toast.style.boxShadow = '0 2px 5px rgba(0,0,0,0.1)';
    const deleteButton = document.createElement('button');
    deleteButton.className = 'delete';
    deleteButton.type = 'button';
    deleteButton.onclick = () => {
       toast.style.opacity = '0';
       setTimeout(() => toast.remove(), 300);
    };
    toast.appendChild(deleteButton);
    toast.appendChild(document.createTextNode(message));
    toastContainer.appendChild(toast);
    setTimeout(() => toast.style.opacity = '1', 10);
    const timeoutId = setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => toast.remove(), 300);
    }, duration);
    deleteButton.addEventListener('click', () => clearTimeout(timeoutId));
}

// General notification closer
document.body.addEventListener('click', function(event) {
  if (event.target.matches('.notification > .delete')) {
    if (!event.target.closest('#toast-container')) {
       event.target.parentElement.remove();
    }
  }
});

// Dropdown adjustment logic
function adjustDropdownDirection(dropdownId) {
  const dropdown = document.getElementById(dropdownId);
  if (!dropdown) return;
  const menu = dropdown.querySelector('.dropdown-menu');
  if (!menu) return;
  const trigger = dropdown.querySelector('.dropdown-trigger button');
  if (!trigger) return;
  const tableContainer = trigger.closest('.table-container');
  if (!tableContainer) return;

  requestAnimationFrame(() => {
    const menuHeight = menu.offsetHeight;
    if (menuHeight === 0) {
      dropdown.classList.remove('is-up');
      return;
    }
    const triggerRect = trigger.getBoundingClientRect();
    const containerRect = tableContainer.getBoundingClientRect();
    const spaceBelow = containerRect.bottom - triggerRect.bottom;
    if (spaceBelow < menuHeight) {
      dropdown.classList.add('is-up');
    } else {
      dropdown.classList.remove('is-up');
    }
  });
}
// ---------------------------------------------------------------------------
// Shared client helpers (window.Legate)
//
// Centralizes the fetch + JSON + error + result-rendering logic that the agent
// and auth views previously each copy-pasted. The CSRF token is added by the
// global fetch() wrapper above, so callers never deal with it directly.
// ---------------------------------------------------------------------------
window.Legate = window.Legate || {};

// Same escaper exposed at window.escapeHtml; namespaced alias for new callers.
Legate.escapeHtml = window.escapeHtml;

// Perform a JSON request. Resolves with the parsed body; rejects with an Error
// whose .message is the server-provided message when available (and .status /
// .data carry the response code and payload).
Legate.apiRequest = function (url, options) {
  options = options || {};
  var headers = new Headers(options.headers || {});
  if (!headers.has('Accept')) headers.set('Accept', 'application/json');
  options.headers = headers;
  return fetch(url, options).then(function (response) {
    return response.json().catch(function () { return {}; }).then(function (data) {
      if (!response.ok) {
        var err = new Error((data && (data.error || data.message)) || ('Request failed (' + response.status + ')'));
        err.status = response.status;
        err.data = data;
        throw err;
      }
      return data;
    });
  });
};

// Render a danger notification (escaped) into a container element.
Legate.renderError = function (el, message) {
  if (!el) return;
  el.innerHTML = '<div class="notification is-danger">' + Legate.escapeHtml(message) + '</div>';
};

// Render a list of { status, <labelKey>, message } items as small Bulma
// notifications. Used by the auth credential/scheme/flow result panels.
Legate.renderTestItems = function (items, opts) {
  opts = opts || {};
  var labelKey = opts.labelKey || 'name';
  var neutralClass = opts.neutralClass || 'is-warning';
  return (items || []).map(function (item) {
    var statusClass = item.status === 'passed' ? 'is-success'
      : item.status === 'failed' ? 'is-danger' : neutralClass;
    return '<div class="notification ' + statusClass + ' is-small">' +
      '<strong>' + Legate.escapeHtml(item[labelKey]) + ':</strong> ' +
      Legate.escapeHtml(item.message) + '</div>';
  }).join('');
};
