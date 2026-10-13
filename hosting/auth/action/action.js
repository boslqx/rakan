// Handles the links in Rakan's account emails. Firebase appends
// ?mode=<action>&oobCode=<one-time code> to this page's URL; each mode is
// completed through the Firebase Auth REST API, so the page needs no SDK.
// https://firebase.google.com/docs/reference/rest/auth

// The project's web API key (also in lib/firebase_options.dart). It only
// identifies the project; it isn't a secret.
const API_KEY = 'AIzaSyDcWgN2o1610hKvFmZuLOYmmPf-Xap2j34';
const ENDPOINT = 'https://identitytoolkit.googleapis.com/v1/accounts';

// Same checklist as Validators.passwordRequirements in the app.
const RULES = [
  ['At least 8 characters', (v) => v.length >= 8],
  ['One lowercase letter', (v) => /[a-z]/.test(v)],
  ['One uppercase letter', (v) => /[A-Z]/.test(v)],
  ['One number', (v) => /\d/.test(v)],
  ['One symbol (!, @, #, ...)', (v) => /[!@#$%^&*(),.?":{}|<>_\-]/.test(v)],
];

// Hold the loading state at least this long so the mark finishes its
// entrance before the result lands on it.
const MIN_LOADING_MS = 1100;

const $ = (id) => document.getElementById(id);
const page = document.querySelector('.page');
const mark = document.querySelector('.mark');
const panel = document.querySelector('.panel');
const startedAt = performance.now();

const params = new URLSearchParams(location.search);
const mode = params.get('mode');
const oobCode = params.get('oobCode');

class ActionError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

async function call(method, body) {
  let res;
  try {
    res = await fetch(`${ENDPOINT}:${method}?key=${API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  } catch {
    throw new ActionError('NETWORK');
  }
  const data = await res.json().catch(() => ({}));
  // Error messages look like "EXPIRED_OOB_CODE" or "WEAK_PASSWORD : details".
  if (!res.ok) throw new ActionError(String(data?.error?.message ?? 'UNKNOWN').split(/[\s:]/)[0]);
  return data;
}

const settle = () =>
  new Promise((r) => setTimeout(r, Math.max(0, MIN_LOADING_MS - (performance.now() - startedAt))));

// ── Rendering ────────────────────────────────────────────────────────────

/**
 * Message text as parts: strings are plain, one-element arrays are bold.
 * Built with text nodes so values like the email are never parsed as HTML.
 */
function renderMessage(parts = []) {
  const el = $('message');
  el.replaceChildren(
    ...parts.map((p) => {
      if (!Array.isArray(p)) return document.createTextNode(p);
      const strong = document.createElement('strong');
      strong.textContent = p[0];
      return strong;
    }),
  );
}

function renderActions(actions = []) {
  $('actions').replaceChildren(
    ...actions.map((a) => {
      if (a.hint) {
        const p = document.createElement('p');
        p.className = 'hint';
        p.textContent = a.hint;
        return p;
      }
      const b = document.createElement('button');
      b.type = 'button';
      b.className = a.primary ? 'button' : 'link';
      if (a.primary) {
        b.innerHTML = '<span class="button-label"></span><span class="spinner" aria-hidden="true"></span>';
        b.querySelector('.button-label').textContent = a.label;
      } else {
        b.textContent = a.label;
      }
      b.addEventListener('click', () => a.onClick(b));
      return b;
    }),
  );
}

let shown = false;

/** state: loading | ready | success | error */
function show({ state, title, message, actions, form = false }) {
  page.dataset.state = state;
  mark.classList.toggle('busy', state === 'loading');
  $('title').textContent = title;
  document.title = `${title} · Rakan`;
  renderMessage(message);
  renderActions(actions);
  $('reset-form').hidden = !form;
  // The first state rides the page's entrance; later ones get their own.
  if (shown) {
    panel.classList.remove('swap');
    void panel.offsetWidth;
    panel.classList.add('swap');
  }
  shown = true;
}

// What to do next when a link is dead, per kind of email.
const NEXT_STEP = {
  verify: ['Open Rakan and tap ', ['Resend email'], ' to get a new link.'],
  reset: ['Open Rakan and tap ', ['Forgot?'], ' on the login screen to get a new link.'],
  other: ['Open the most recent email from Rakan and use the link there.'],
};

function showError(error, { kind, retry }) {
  const next = NEXT_STEP[kind];
  const tryAgain = { label: 'Try again', primary: true, onClick: retry };
  switch (error.code) {
    case 'EXPIRED_OOB_CODE':
      return show({
        state: 'error',
        title: 'This link has expired',
        message: ['For your security, links in our emails only work for a limited time. ', ...next],
      });
    case 'INVALID_OOB_CODE':
      return show({
        state: 'error',
        title: 'This link can’t be used',
        message:
          kind === 'verify'
            ? ['It may have been used already. If you’ve verified, you’re all set, so just open Rakan. If not, ', ...lower(next)]
            : ['It may have been used already, or copied only in part. ', ...next],
      });
    case 'USER_DISABLED':
      return show({ state: 'error', title: 'Account disabled', message: ['This Rakan account has been disabled.'] });
    case 'USER_NOT_FOUND':
    case 'EMAIL_NOT_FOUND':
      return show({ state: 'error', title: 'Account not found', message: ['The account this link was for no longer exists.'] });
    case 'TOO_MANY_ATTEMPTS_TRY_LATER':
      return show({
        state: 'error',
        title: 'Too many attempts',
        message: ['Please wait a few minutes, then try again.'],
        actions: [tryAgain],
      });
    case 'NETWORK':
      return show({
        state: 'error',
        title: 'Couldn’t connect',
        message: ['Check your internet connection and try again.'],
        actions: [tryAgain],
      });
    default:
      return show({
        state: 'error',
        title: 'Something went wrong',
        message: ['We couldn’t complete this request. Please try again.'],
        actions: [tryAgain],
      });
  }
}

/** Lower-cases the first letter of a message so it can follow a comma. */
function lower([first, ...rest]) {
  return [first.charAt(0).toLowerCase() + first.slice(1), ...rest];
}

// ── Modes ────────────────────────────────────────────────────────────────

async function verifyEmail() {
  show({ state: 'loading', title: 'Verifying your email', message: ['Just a moment…'] });
  try {
    const { email } = await call('update', { oobCode });
    await settle();
    show({
      state: 'success',
      title: 'Email verified',
      message: ['Thanks! ', [email], ' is confirmed. Head back to the Rakan app and it’ll carry on by itself in a few seconds.'],
      actions: [{ hint: 'You can close this page.' }],
    });
  } catch (e) {
    await settle();
    showError(e, { kind: 'verify', retry: verifyEmail });
  }
}

async function verifyAndChangeEmail() {
  show({ state: 'loading', title: 'Updating your email', message: ['Just a moment…'] });
  try {
    const { email } = await call('update', { oobCode });
    await settle();
    show({
      state: 'success',
      title: 'Email updated',
      message: ['From now on, sign in to Rakan with ', [email], '.'],
      actions: [{ hint: 'You can close this page.' }],
    });
  } catch (e) {
    await settle();
    showError(e, { kind: 'other', retry: verifyAndChangeEmail });
  }
}

async function recoverEmail() {
  show({ state: 'loading', title: 'Restoring your email', message: ['Just a moment…'] });
  try {
    const { email } = await call('update', { oobCode });
    await settle();
    show({
      state: 'success',
      title: 'Email restored',
      message: [
        'Your sign-in email is back to ', [email],
        '. If you didn’t ask for it to be changed, reset your password now to keep your account safe.',
      ],
      actions: [{ label: 'Send password reset email', primary: true, onClick: (b) => sendReset(b, email) }],
    });
  } catch (e) {
    await settle();
    showError(e, { kind: 'other', retry: recoverEmail });
  }
}

async function sendReset(button, email) {
  button.classList.add('loading');
  button.disabled = true;
  try {
    await call('sendOobCode', { requestType: 'PASSWORD_RESET', email });
    show({
      state: 'success',
      title: 'Check your inbox',
      message: ['We’ve sent a password reset link to ', [email], '.'],
      actions: [{ hint: 'You can close this page.' }],
    });
  } catch (e) {
    showError(e, { kind: 'other', retry: () => sendReset(button, email) });
  }
}

async function resetPassword() {
  show({ state: 'loading', title: 'Checking your link', message: ['Just a moment…'] });
  let email;
  try {
    ({ email } = await call('resetPassword', { oobCode }));
  } catch (e) {
    await settle();
    return showError(e, { kind: 'reset', retry: resetPassword });
  }
  await settle();
  show({ state: 'ready', title: 'Choose a new password', message: ['For ', [email]], form: true });
  setUpResetForm(email);
}

function setUpResetForm(email) {
  const form = $('reset-form');
  const password = $('password');
  const confirm = $('confirm');
  const submit = $('submit');
  const error = $('form-error');
  const reveal = form.querySelector('.reveal');
  $('username').value = email;

  const items = RULES.map(([label]) => {
    const li = document.createElement('li');
    li.textContent = label;
    return li;
  });
  $('rules').replaceChildren(...items);

  // A rejection from the server stays up until they edit a field.
  let serverError = '';

  const update = () => {
    const v = password.value;
    let allMet = true;
    RULES.forEach(([, test], i) => {
      const met = test(v);
      items[i].classList.toggle('met', met);
      allMet &&= met;
    });
    // Only complain about a mismatch once they've typed enough to judge.
    const mismatch = confirm.value !== '' && confirm.value !== v && confirm.value.length >= v.length;
    confirm.setAttribute('aria-invalid', String(mismatch));
    error.textContent = mismatch ? 'Passwords don’t match.' : serverError;
    submit.disabled = !(allMet && confirm.value === v);
  };
  const onEdit = () => {
    serverError = '';
    update();
  };
  password.addEventListener('input', onEdit);
  confirm.addEventListener('input', onEdit);
  update();

  reveal.addEventListener('click', () => {
    const showing = reveal.getAttribute('aria-pressed') !== 'true';
    reveal.setAttribute('aria-pressed', String(showing));
    reveal.setAttribute('aria-label', showing ? 'Hide password' : 'Show password');
    password.type = confirm.type = showing ? 'text' : 'password';
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (submit.disabled) return;
    submit.classList.add('loading');
    submit.disabled = true;
    serverError = '';
    error.textContent = '';
    try {
      await call('resetPassword', { oobCode, newPassword: password.value });
      show({
        state: 'success',
        title: 'Password updated',
        message: ['You can now log in to Rakan with your new password.'],
        actions: [{ hint: 'You can close this page.' }],
      });
    } catch (e) {
      submit.classList.remove('loading');
      if (e.code === 'WEAK_PASSWORD' || e.code === 'PASSWORD_DOES_NOT_MEET_REQUIREMENTS') {
        serverError = 'That password isn’t strong enough. Try a longer one.';
        update();
        return;
      }
      if (e.code === 'NETWORK') {
        serverError = 'Couldn’t connect. Check your internet and try again.';
        update();
        return;
      }
      showError(e, { kind: 'reset', retry: resetPassword });
    }
  });

  // Jump straight in on desktop; on phones a keyboard popping up over the
  // page before they've read it is more jarring than helpful.
  if (matchMedia('(pointer: fine)').matches) password.focus();
}

// ── Start ────────────────────────────────────────────────────────────────

const MODES = { verifyEmail, verifyAndChangeEmail, recoverEmail, resetPassword };

if (oobCode && MODES[mode]) {
  MODES[mode]();
} else {
  settle().then(() =>
    show({
      state: 'error',
      title: 'Link not recognised',
      message: ['This page opens links from Rakan’s emails. Try tapping the link in your email again.'],
    }),
  );
}
