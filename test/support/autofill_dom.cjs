// Uses only Node built-ins; all credentials and page state are test fixtures.
const vm = require('node:vm');
const {script, url, iframe, tamperString} = JSON.parse(process.argv[2]);
let reads = 0;
let events = 0;
class Input {
  constructor(type, name) {
    this.type = type;
    this.name = name;
    this.storedValue = '';
  }
  get value() { return this.storedValue; }
  set value(value) { this.storedValue = value; }
  getBoundingClientRect() { return {width: 100, height: 30}; }
  getAttribute() { return null; }
  focus() {}
  blur() {}
  dispatchEvent() { events++; }
}
const username = new Input('text', 'username');
const password = new Input('password', 'password');
const document = {
  querySelectorAll() { reads++; return [username, password]; },
};
const context = vm.createContext({
  location: new URL(url),
  getComputedStyle: () => ({visibility: 'visible', display: 'block', opacity: '1'}),
  document,
  HTMLInputElement: Input,
  HTMLTextAreaElement: class {},
  Event: class {},
  KeyboardEvent: class {},
});
vm.runInContext('this.window = this; this.top = this;', context);
if (iframe) vm.runInContext('this.top = {};', context);
if (tamperString) {
  vm.runInContext(`
    String.prototype.indexOf = () => 0;
    String.prototype.startsWith = () => true;
    const prefix = '/auth/realms/school-a/';
    for (let i = this.location.pathname.length; i < prefix.length; i++) {
      Object.defineProperty(String.prototype, i, {value: prefix[i]});
    }
    // A page may shadow global names; the actual global object's location wins.
    this.window = { location: {
      protocol: 'https:', origin: 'https://identity.school.example',
      pathname: '/auth/realms/school-a/login'
    }};
    this.window.top = this.window;
  `, context);
}
const result = vm.runInContext(script, context, {timeout: 1000});
process.stdout.write(JSON.stringify({
  result, reads, events, username: username.value, password: password.value,
}));
