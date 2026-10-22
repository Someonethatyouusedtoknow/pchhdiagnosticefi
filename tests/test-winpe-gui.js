// Run with node tests/test-winpe-gui.js. Exercise the HTA's real job protocol without Windows COM.
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const hta = fs.readFileSync('winpe/Windows/System32/pchh-gui.hta', 'utf8');
const backend = fs.readFileSync('winpe/Windows/System32/startnet.cmd', 'utf8');
const nodes = {}, disk = {}, launches = [], alerts = [];
const context = {
  document: {documentElement:{clientWidth:1280,clientHeight:800},body:{},getElementById(id) {return nodes[id] || (nodes[id] = {style:{},styleSheet:{cssText:''},value:'',innerText:'',checked:true,focus(){}});}},
  window: {setInterval(){return 1;},clearInterval(){},setTimeout(){}},
  screen: {width:1280,height:800},
  alert(s){alerts.push(s);}, confirm(){return true;},
  ActiveXObject: function(name) {
    if(name == 'WScript.Shell') return {
      ExpandEnvironmentStrings(s){return s.replace('%TEMP%', 'X:\\Temp').replace('%SystemRoot%', 'X:\\Windows');},
      Run(command,style,wait){launches.push({command,style,wait});}
    };
    return {
      CreateFolder(){}, CreateTextFile(path){return {Write(s){disk[path]=s;},Close(){}};},
      FileExists(path){return path in disk;},
      OpenTextFile(path){return {AtEndOfStream:!disk[path],ReadAll(){return disk[path];},Close(){}};},
      MoveFile(from,to){disk[to]=disk[from];delete disk[from];},
      CopyFile(from,to){disk[to]=disk[from];}
    };
  }
};
vm.createContext(context);
vm.runInContext(hta.match(/<script language="JScript">([\s\S]*?)<\/script>/)[1], context);
assert.equal(context.catalog.length,11);
for(const [,items] of context.catalog) for(const [,action] of items) {
  if(action[0]=='@') continue;
  assert(backend.includes('goto '+action+'\n'), action+' missing dispatcher');
  assert(backend.includes('\n:'+action+'\n'), action+' missing implementation');
}
context.submenu(1);
assert(nodes.menus.innerHTML.includes('Format a volume'));
context.startJob('DISK_FORMAT','Format a volume',null);
const dir = context.job.dir;
assert.equal(launches.length,1);
assert.equal(launches[0].style,0,'CMD must run hidden');
assert.equal(launches[0].wait,false);
assert(disk[dir+'\\run.cmd'].includes('/gui DISK_FORMAT'));
assert(disk[dir+'\\run.cmd'].includes('<nul'));
assert(disk[dir+'\\run.cmd'].includes('done.txt'));
disk[dir+'\\output.txt']='Disk output <not markup>\r\n';
disk[dir+'\\request.txt']='1\r\nv\r\nVolume number:\r\n';
context.poll();
assert.equal(nodes.log.innerText,'Disk output <not markup>\r\n');
assert.equal(nodes.prompt.style.display,'block');
nodes.answer.value='1 & format C:';
context.submitAnswer();
assert(alerts.length);
assert(!disk[dir+'\\answer-1.txt']);
nodes.answer.value='2';context.submitAnswer();
assert.equal(disk[dir+'\\answer-1.txt'],'2\r\n');
context.poll();assert.equal(nodes.prompt.style.display,'none','stale request must not reappear');
disk[dir+'\\request.txt']='2\r\npassword\r\nNetwork password:\r\n';
context.poll();assert.equal(nodes.secret.style.display,'inline');
nodes.secret.value='secret123';context.submitAnswer();
assert.equal(nodes.secret.value,'');assert(!nodes.log.innerText.includes('secret123'));
disk[dir+'\\done.txt']='1223\r\n';context.poll();
assert.equal(context.job,null);assert.equal(nodes.status.innerText,'Cancelled');
assert.equal(nodes.back.disabled,false);
context.editor('diskpart','DiskPart');
assert.equal(nodes.script.value,'list disk\r\nlist volume');
context.runScript();
assert(disk[context.job.dir+'\\commands.txt'].endsWith('\r\nexit\r\n'));
assert(disk[context.job.dir+'\\run.cmd'].includes('diskpart /s'));
assert.equal(launches[1].style,0);
console.log('WinPE GUI: catalog coverage, hidden execution, output, prompts, input validation, cancellation and script runner passed');

// Initial setup must advance without requiring a novice to find Back to tools.
context.job=null;context.startJob('GUI_INIT','Preparing recovery environment',null);
assert(nodes.status.innerText.includes('open automatically'));
disk[context.job.dir+'\\done.txt']='0';context.poll();
assert.equal(nodes.heading.innerText,'Recovery Tools');
assert.equal(nodes.work.style.display,'none');
assert.equal(nodes.menus.style.display,'block');
context.startJob('GUI_INIT','Preparing recovery environment',null);
disk[context.job.dir+'\\done.txt']='1';context.poll();
assert.equal(nodes.work.style.display,'block');
assert(nodes.status.innerText.includes('Setup could not finish'));
console.log('Startup automatically opens tools on completion and preserves setup errors');

// Navigation/search must preserve the selected tool's backend action.
context.home();
assert.equal(nodes.overview.style.display,'block');
assert.equal((nodes.menus.innerHTML.match(/class="card-button"/g)||[]).length,11);
nodes.search.value='uefi';context.searchTools();
assert(nodes.menus.innerHTML.includes('Rebuild UEFI boot files'));
assert(!nodes.menus.innerHTML.includes('Copy folders with RoboCopy'));
assert.equal(nodes.overview.style.display,'none');
context.openTool(2,1);
assert(disk[context.job.dir+'\\run.cmd'].includes('/gui BOOT_UEFI'));
const activeHeading=nodes.heading.innerText;
context.home();context.submenu(6);context.editor('cmd','Run commands');
assert.equal(nodes.heading.innerText,activeHeading,'navigation must not hide a running operation');
disk[context.job.dir+'\\done.txt']='0';context.poll();context.back();
assert.equal(nodes.heading.innerText,'Boot Repair');
context.home();nodes.search.value='nothing <script>';context.searchTools();
assert(nodes.menus.innerHTML.includes('No matching tools'));
assert(!nodes.menus.innerHTML.includes('<script>'));
nodes.search.value='';context.searchTools();
assert.equal(nodes.overview.style.display,'block');
context.submenu(1);
assert(nodes.menus.innerHTML.includes('ERASES DATA'));
assert.equal(nodes["search-wrap"].style.display,"none");
console.log('Revamped navigation: search, action routing, active-operation guard, back navigation and destructive labels passed');

context.job=null;
const before=launches.length;
context.editor('cmd','Run commands');
assert.equal(launches.length,before+1);
assert.equal(launches[before].style,1,'Command Prompt must be visible');
assert.equal(launches[before].wait,false);
assert(launches[before].command.endsWith('cmd.exe" /d /k'));
assert.equal(context.job,null,'interactive CMD must not become a hidden GUI job');
assert(backend.includes('call :STOR_LOAD_FOLDER "%SystemDrive%\\PCHH\\Drivers"'));
assert(!/echo select volume [^&\r\n]*noerr/.test(backend));
assert(backend.includes('pnputil /scan-devices'));
console.log('Visible interactive Command Prompt and RAM-resident storage driver loading checks passed');

// Reflow at actual viewport dimensions; never shrink/resample the whole GUI.
function viewport(w,h){context.document.documentElement.clientWidth=w;context.document.documentElement.clientHeight=h;context.layout();}
for(const [w,h] of [[1920,1080],[1280,800],[1024,768],[800,600],[640,480]]){
 viewport(w,h);
 assert.equal(nodes.app.style.width,w+'px');
 assert.equal(nodes.app.style.height,h+'px');
 assert.equal(nodes.app.style.zoom,undefined);
 const css=nodes['text-sizing'].styleSheet.cssText;
 const sizes=[...css.matchAll(/font-size:(\d+)px/g)].map(m=>Number(m[1]));
 assert(sizes.length>5);
 assert(sizes.every(n=>n>=12),'keep text readable on small displays');
}
assert(nodes.app.className.includes('narrow'));
assert(nodes.app.className.includes('short'));
context.screen.width=3840;context.screen.height=2160;
viewport(960,540);assert.equal(nodes.app.style.width,'960px');
context.changeTextSize(1);assert.equal(context.uiTextSize,16);
assert(nodes['text-sizing'].styleSheet.cssText.includes('font-size:16px'));
context.layout();assert.equal(context.uiTextSize,16);
context.changeTextSize(0);assert.equal(context.uiTextSize,15);
assert.equal(nodes['scale-label'].innerText,'15px');
for(let i=0;i<20;i++)context.changeTextSize(-1);
assert.equal(context.uiTextSize,13);
for(let i=0;i<20;i++)context.changeTextSize(1);
assert.equal(context.uiTextSize,22);
assert(!hta.includes('style.zoom'),'do not resample the interface');
assert(!hta.includes('window.resizeTo'));
assert(!hta.includes('@media'));
console.log('Native-size GUI: responsive reflow, readable fonts, small screens and text controls passed');
