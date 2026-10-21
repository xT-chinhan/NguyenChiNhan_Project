import {Guard} from './guard.js';
const $ = id => document.getElementById(id);
const preset=new URLSearchParams(location.search);
function preselect(id,key) { const value=preset.get(key);if(value && [...$(id).options].some(option=>option.value===value))$(id).value=value; }
let token = '', socket = null, session = null, media = null, guard = null;
let active = false, busy = false, generation = 0, speechGeneration = 0, speaking = false;
let lastSeq = 0, lastCapture = -1, currentInstruction = null;
let speechPurpose = null, lastNotice = '', lastNoticeAt = -Infinity, results = 0, connectionTimer = null;
let pauseReason = '', rejected = 0;
const diagnostics=[];
const detail=document.createElement('details'), summary=document.createElement('summary'), traceView=document.createElement('pre');
summary.textContent='Chi tiết camera và kết nối';detail.append(summary,traceView);$('telemetry').after(detail);
function trace(code) { diagnostics.push(`${new Date().toLocaleTimeString('vi-VN')} ${code}`);if(diagnostics.length>16)diagnostics.shift();traceView.textContent=diagnostics.join('\n'); }
const captures = new Map(), canvas = document.createElement('canvas');
const states = {localizing:'Đang tìm vị trí',navigating:'Đang theo tuyến',lost:'Mất định vị',paused:'Đã tạm dừng',completed:'Đã đến đích',stopped:'Đã kết thúc'};
const now = () => performance.now();
function message(text) { $('message').textContent = text; }
function cancelSpeech() { speechGeneration++; window.speechSynthesis?.cancel(); speaking = false; speechPurpose=null; }
function invalidate() { currentInstruction = null; if(speechPurpose==='instruction')cancelSpeech(); }
function voice(utterance) {
  utterance.lang='vi-VN';
  const available=window.speechSynthesis.getVoices();
  const vietnamese=available.find(item=>/^vi(?:-|$)/i.test(item.lang));
  if(vietnamese)utterance.voice=vietnamese;
}
function notice(text,force=false) {
  if(!force && (!$('audio').checked || currentInstruction || document.hidden))return;
  if(!window.speechSynthesis || !window.SpeechSynthesisUtterance){$('audio-status').textContent='Trình duyệt này không hỗ trợ đọc. Mở link bằng Chrome hoặc Safari.';return;}
  if(!force && (text===lastNotice || now()-lastNoticeAt<15000))return;
  lastNotice=text;lastNoticeAt=now();cancelSpeech();speechPurpose='status';
  const run=speechGeneration, utterance=new SpeechSynthesisUtterance(text);voice(utterance);
  $('audio-status').textContent='Đang yêu cầu trình duyệt phát giọng nói…';
  utterance.onstart=()=>{if(run!==speechGeneration)return;speaking=true;$('audio-status').textContent='Trình duyệt đã bắt đầu đọc. Nếu không nghe, kiểm tra âm lượng đa phương tiện.';};
  utterance.onend=()=>{if(run===speechGeneration){speaking=false;speechPurpose=null;}};
  utterance.onerror=event=>{if(run===speechGeneration){speaking=false;speechPurpose=null;$('audio-status').textContent=`Không phát được giọng nói (${event.error}). Bấm Thử loa; mở trang trong Chrome/Safari thay vì trình duyệt Zalo.`;}};
  window.speechSynthesis.resume();window.speechSynthesis.speak(utterance);
}
$('test-audio').onclick=()=>notice('Đây là kiểm tra loa tiếng Việt. Ứng dụng chưa xác nhận đường đi tại vị trí của bạn.',true);
$('audio').onchange=()=>{if(!$('audio').checked)cancelSpeech();};
function captureFailure(error) {
  const reasons={CAMERA_FRAME_UNSUPPORTED:'Trình duyệt không cung cấp cách xác nhận khung hình mới. Mở bằng Chrome/Safari bản mới.',CAMERA_TIMEOUT:'Camera không tạo được khung hình mới trong 300 ms. Giữ trang ở phía trước và thử lại.',CAMERA_EMPTY:'Camera chưa có hình ảnh.',IMAGE_LIMIT:'Ảnh chụp quá lớn hoặc chụp mất hơn một giây.',PROTOCOL:'Yêu cầu chụp ảnh từ server không hợp lệ.'};
  const code=Object.hasOwn(reasons,error.message)?error.message:'CLIENT_PROCESSING_ERROR';trace(code);
  pause(`${reasons[code] || 'Trình duyệt gặp lỗi xử lý phản hồi từ server.'} [${code}]`);
}
function freshCameraFrame(video) {
  return new Promise((resolve,reject)=>{
    const quality=()=>video.getVideoPlaybackQuality?.().totalVideoFrames;
    const baseline=quality();let finished=false, callback=null, poll=null;
    const finish=(error)=>{if(finished)return;finished=true;clearTimeout(timer);clearInterval(poll);if(callback!==null)video.cancelVideoFrameCallback?.(callback);error?reject(error):resolve();};
    const timer=setTimeout(()=>finish(new Error('CAMERA_TIMEOUT')),300);
    if(typeof video.requestVideoFrameCallback==='function')callback=video.requestVideoFrameCallback(()=>finish());
    else if(!Number.isFinite(baseline)){finish(new Error('CAMERA_FRAME_UNSUPPORTED'));return;}
    // A count increase proves a new decoded frame; currentTime alone does not.
    if(Number.isFinite(baseline))poll=setInterval(()=>{if(quality()>baseline && video.readyState>=2)finish();},16);
  });
}
function holdText(reason) {
  return {LOCALIZING:'Server đang nhận ảnh nhưng chưa nhận ra điểm trên tuyến đã chọn. Đứng gần điểm đầu và hướng camera như ảnh tham chiếu.',LOST:'Không nhận ra vị trí trên tuyến. Hướng dẫn di chuyển đang tạm dừng.',LOCALIZATION_LOST:'Chưa nhận ra vị trí trên tuyến trong thời gian cho phép. Đứng lại đúng điểm đầu hoặc điểm vừa xác nhận rồi bấm Tiếp tục.',STREAM_STALE:'Chưa nhận được ảnh mới kịp thời. Hãy kiểm tra mạng và bấm Tiếp tục.',PAUSE:'Phiên đã tạm dừng.',VISION_UNAVAILABLE:'AI trên server chưa sẵn sàng xử lý ảnh.',OUTPUT_BACKPRESSURE:'Luồng trả kết quả bị nghẽn. Kết thúc phiên và kết nối lại.',AUTH_INVALID:'Mã thiết bị không còn hợp lệ. Kết thúc phiên và kết nối lại.'}[reason] || 'Hướng dẫn di chuyển đang tạm dừng.';
}
function state(value) { $('state').textContent = states[value] || value; $('dot').classList.toggle('active', value === 'navigating'); }
function send(value) { if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(value)); }
async function api(path, options = {}) {
  const response = await fetch(path, {...options, headers:{'Authorization':`Bearer ${token}`,'Content-Type':'application/json',...options.headers},cache:'no-store'});
  if (!response.ok) {
    const code = (await response.json().catch(() => null))?.error?.code;
    throw new Error(code || `HTTP_${response.status}`);
  }
  return response.status === 204 ? null : response.json();
}
function safeError(error) {
  const known = {NotAllowedError:'Chưa được cấp quyền camera.',NotFoundError:'Không tìm thấy camera.',NotReadableError:'Camera đang bận.',AUTH_INVALID:'Token không hợp lệ hoặc đã hết hạn.',DEVICE_SESSION_EXISTS:'Thiết bị đang có phiên khác. Hãy kết thúc phiên đó trước.',VISION_UNAVAILABLE:'AI trên server chưa sẵn sàng.',SESSION_CAPACITY:'Server đã đủ số phiên.'};
  message(known[error.name] || known[error.message] || 'Không thể thực hiện. Kiểm tra token, kết nối và trạng thái server.');
}
async function pages(path) {
  const items = []; let cursor = null;
  do {
    const result = await api(path + (path.includes('?') ? '&' : '?') + 'limit=100' + (cursor ? '&cursor='+encodeURIComponent(cursor) : ''));
    items.push(...result.items); cursor = result.next_cursor;
  } while (cursor && items.length < 1000);
  return items;
}
function select(id, items) {
  $(id).replaceChildren(...items.map(item => { const option=document.createElement('option');option.value=item.id;option.textContent=item.name;return option; }));
}
async function places() {
  select('route', []);
  const items = await pages(`/v1/maps/${$('map').value}/places`);
  select('from',items);select('to',items);if(items.length>1)$('to').selectedIndex=1;
}
$('connect').onclick = async () => {
  if (session) return;
  token = $('token').value.trim(); $('token').value = '';
  if (!/^navdev_[A-Za-z0-9_-]{43}$/.test(token)) { token='';message('Nhập token thiết bị dạng navdev_…');return; }
  try {
    const ready = await fetch('/health/ready',{cache:'no-store'});
    if (!ready.ok) throw new Error('VISION_UNAVAILABLE');
    select('map',await pages('/v1/maps'));
    $('catalog').hidden=false;preselect('map','map');if($('map').value)await places();
    preselect('from','from');preselect('to','to');
    state('Đã kết nối');message('Chọn điểm đầu và điểm đến của tuyến đã khảo sát.');
    if(preset.has('map') && preset.has('from') && preset.has('to'))$('find').click();
  } catch(error) { token='';safeError(error); }
};
$('map').onchange = () => places().catch(safeError);
$('from').onchange = $('to').onchange = () => select('route', []);
$('find').onclick = async () => {
  try {
    const query = new URLSearchParams({map_id:$('map').value,from_place_id:$('from').value,to_place_id:$('to').value});
    const result=await api('/v1/routes?'+query);select('route',result.items);
    message(result.items.length ? 'Đã có tuyến. Đứng tại điểm đầu rồi bật camera.' : 'Chưa có tuyến đã khảo sát giữa hai điểm này.');
  } catch(error) { safeError(error); }
};
function cameraOff() { media?.getTracks().forEach(track=>track.stop());media=null;$('video').srcObject=null; }
async function cameraOn() {
  if (media?.getVideoTracks().some(track=>track.readyState==='live')) return;
  if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) throw new Error('SECURE_CONTEXT');
  media=await navigator.mediaDevices.getUserMedia({audio:false,video:{facingMode:{ideal:'environment'},width:{ideal:640},height:{ideal:480}}});
  if (document.hidden) {cameraOff();throw new Error('HIDDEN');}
  for (const track of media.getVideoTracks()) track.addEventListener('ended',()=>pause('Camera đã ngừng. Hướng dẫn tạm dừng.'));
  $('video').srcObject=media;await $('video').play();
}
function controls(enabled) {
  for(const id of ['pause','resume','repeat','stop'])$(id).disabled=!enabled;
  for(const id of ['start','connect','find','map','from','to','route'])$(id).disabled=enabled;
}
async function start() {
  if (session || !token || !$('route').value) {message('Kết nối thiết bị và chọn tuyến trước.');return;}
  const run=++generation;pauseReason='';rejected=0;trace('START_CAMERA'); $('start').disabled=true;
  if($('audio').checked)notice('Đang bật camera và kết nối máy chủ. Đây là bản thử kết nối.',true);
  message('Đang bật camera…');
  try {
    await cameraOn();
    if (run!==generation) return;
    session=await api('/v1/sessions',{method:'POST',body:JSON.stringify({route_id:$('route').value,sensor:{mode:'rgb'},language:'vi-VN'})});
    if(run!==generation || document.hidden){await stop(false);return;}
    guard=new Guard(now());captures.clear();lastSeq=0;lastCapture=-1;results=0;controls(true);
    state('Đang nối luồng ảnh');message('Camera đã bật. Đang chờ xác thực WebSocket…');
    $('telemetry').textContent='Camera đã bật; chưa nhận kết quả AI.';
    connectionTimer=setTimeout(()=>{if(run===generation){pause('Không nhận được phản hồi luồng ảnh sau 10 giây. Kết thúc phiên rồi thử lại trong Chrome/Safari.');socket?.close();}},10000);
    socket=new WebSocket(`${location.protocol==='https:'?'wss:':'ws:'}//${location.host}/v1/mobile/sessions/${session.id}/stream`);
    socket.onopen=()=>{trace('WS_OPEN');send({type:'auth',token});};
    socket.onmessage=event=> { try {if(run===generation)handle(JSON.parse(event.data),run).catch(captureFailure);} catch {pause('Dữ liệu server không hợp lệ. [PROTOCOL]');} };
    socket.onclose=event=>{clearTimeout(connectionTimer);trace(`WS_CLOSED_${event.code}`);if(run===generation){active=false;invalidate();state('paused');if(!pauseReason){pauseReason=`Mất kết nối luồng ảnh [WS_${event.code}]. Kết thúc phiên rồi kết nối lại.`;if($('audio').checked)notice(pauseReason,true);}message(pauseReason);cameraOff();}};
    socket.onerror=()=>pause('Không kết nối được luồng ảnh.');
  } catch(error) { await stop(false);if(error.message==='SECURE_CONTEXT')message('Camera cần HTTPS hoặc localhost qua USB.');else safeError(error); }
  finally {if(!session)controls(false);}
}
$('start').onclick=()=>start();
async function capture(request,run) {
  if (!active || busy || document.hidden) return;
  if (!Number.isInteger(request.seq) || request.seq<=lastSeq || request.deadline_ms!==1000) throw new Error('PROTOCOL');
  busy=true;lastSeq=request.seq;const requested=now();
  try {
    const video=$('video');
    trace(`CAPTURE_REQUEST #${request.seq}`);
    await freshCameraFrame(video);
    if(run!==generation || !active || document.hidden)return;
    if(!video.videoWidth || !video.videoHeight)throw new Error('CAMERA_EMPTY');
    const scale=Math.min(640/video.videoWidth,480/video.videoHeight,1);
    canvas.width=Math.max(32,Math.floor(video.videoWidth*scale));canvas.height=Math.max(32,Math.floor(video.videoHeight*scale));
    const at=Math.max(Math.floor(now()),lastCapture+1);lastCapture=at;
    canvas.getContext('2d').drawImage(video,0,0,canvas.width,canvas.height);
    const jpeg=canvas.toDataURL('image/jpeg',.75).split(',')[1];
    if(jpeg.length>524288 || now()-requested>=1000)throw new Error('IMAGE_LIMIT');
    trace(`FRAME_SENT #${request.seq} ${canvas.width}x${canvas.height} ${Math.round(now()-requested)}ms`);
    captures.set(request.seq,{at,requested});while(captures.size>8)captures.delete(captures.keys().next().value);
    send({type:'frame',seq:request.seq,frame_token:request.frame_token,capture_monotonic_ms:at,heading_deg:null,heading_accuracy_deg:null,image_b64:jpeg,depth:null});
  } finally {busy=false;}
}
function announce(instruction,received,repeated=false) {
  if(!instruction)return;
  const deadline=guard.instruction(instruction,received,now(),repeated);if(deadline===null)return;
  send({type:'ack',instruction_id:instruction.id,stage:'received'});
  currentInstruction={instruction,deadline};
  cancelSpeech();speechPurpose='instruction';const speechRun=speechGeneration;
  if(!$('audio').checked || !window.speechSynthesis) {
    if(now()>=deadline)return;
    message(instruction.text_vi);send({type:'ack',instruction_id:instruction.id,stage:'presented'});return;
  }
  message(instruction.text_vi);
  const utterance=new SpeechSynthesisUtterance(instruction.text_vi);voice(utterance);
  utterance.onstart=()=>{
    if(speechRun!==speechGeneration || document.hidden || now()>=deadline){cancelSpeech();return;}
    speaking=true;send({type:'ack',instruction_id:instruction.id,stage:'presented'});
  };
  utterance.onend=()=>{if(speechRun===speechGeneration)speaking=false;};
  utterance.onerror=event=>{if(speechRun===speechGeneration){speaking=false;$('audio-status').textContent=`Không đọc được hướng dẫn (${event.error}). Bấm Thử loa để kiểm tra.`;}};
  if(now()<deadline)window.speechSynthesis.speak(utterance);
}
async function handle(value,run) {
  const received=now();
  if(value.type==='welcome'){trace('WS_AUTHENTICATED');clearTimeout(connectionTimer);lastNoticeAt=-Infinity;guard=new Guard(now());message('Đã nối luồng ảnh. Đang chờ kết quả AI đầu tiên…');active=['localizing','navigating','lost'].includes(value.state);state(value.state);return;}
  if(value.type==='capture_request'){await capture(value,run);return;}
  if(value.type==='heartbeat')return;
  if(value.type==='frame_result'){
    const captured=captures.get(value.seq);captures.delete(value.seq);
    if(!guard.outcome(value,captured,received)){trace(`RESULT_EXPIRED #${value.seq}`);pause('Kết quả AI tới sau hạn một giây. Kết nối hiện tại chưa đủ nhanh để dẫn đường. [RESULT_EXPIRED]');return;}
    trace(`FRAME_RESULT #${value.seq} ${Math.round(received-captured.requested)}ms`);
    results++;$('telemetry').textContent=`AI đã xử lý ${results} ảnh · Ảnh gần nhất #${value.seq} · Phát hiện ${value.obstacles?.length ?? 0} vật thể.`;
    state(value.state);$('latency').textContent=`${Math.round(received-captured.requested)} ms`;
    $('progress').textContent=`Điểm đã xác nhận: ${value.last_confirmed_seq<0?'chưa có':value.last_confirmed_seq+1} · Điểm đang tìm: ${value.target_seq+1}`;
    if(value.movement_held){invalidate();message(holdText(value.hold_reason));}
    if(value.instruction && value.instruction.frame_seq===value.seq && value.instruction.capture_monotonic_ms===value.capture_monotonic_ms && !(value.movement_held && value.instruction.priority==='guidance'))announce(value.instruction,received);
    if(value.movement_held && !value.instruction)notice(holdText(value.hold_reason));
    if(['completed','stopped'].includes(value.state)){active=false;cameraOff();}
    return;
  }
  if(value.type==='status'){
    trace(`SERVER_${value.code || value.state}`);
    if(value.state==='paused' && pauseReason){active=false;state('paused');message(pauseReason);return;}
    const warning=currentInstruction && currentInstruction.instruction.priority!=='guidance' && now()<currentInstruction.deadline && !['paused','stopped'].includes(value.state);
    if(!warning){invalidate();message(holdText(value.code));notice(holdText(value.code));}
    state(value.state);
    if(value.state==='paused')active=false;
  } else if(value.type==='control_result'){
    trace(`CONTROL_${value.command}_${value.state}`);
    state(value.state);active=['localizing','navigating','lost'].includes(value.state);
    if(value.command==='repeat' && !(value.movement_held && value.instruction?.priority==='guidance'))announce(value.instruction,received,true);
  } else if(value.type==='frame_rejected'){
    rejected++;trace(`FRAME_REJECTED #${value.seq} ${value.code}`);
    captures.delete(value.seq);invalidate();message(`Ảnh bị server từ chối (${value.code || 'không rõ'}). Đang chờ ảnh tiếp theo.`);$('telemetry').textContent=`Ảnh #${value.seq} chưa được xử lý · ${value.code || 'không rõ'}`;
  } else if(value.type==='error')pause('Phiên không còn khả dụng. Hãy kết thúc và kết nối lại.');
}
function pause(text='Đã tạm dừng.') {pauseReason=text;trace('CLIENT_PAUSE');active=false;invalidate();cancelSpeech();if($('audio').checked)notice(text,true);send({type:'control',command:'pause'});state('paused');message(text);}
$('pause').onclick=()=>pause();
$('resume').onclick=async()=>{if(socket?.readyState!==WebSocket.OPEN){message('Kết thúc phiên và kết nối lại trước.');return;}try{await cameraOn();pauseReason='';trace('CLIENT_RESUME');guard=new Guard(now());active=true;send({type:'control',command:'resume'});message('Đang định vị lại…');}catch(error){safeError(error);}};
$('repeat').onclick=()=>send({type:'control',command:'repeat'});
async function stop(show=true) {
  ++generation;clearTimeout(connectionTimer);active=false;invalidate();cancelSpeech();cameraOff();captures.clear();
  send({type:'control',command:'stop'});socket?.close();socket=null;
  const previous=session;session=null;controls(false);
  if(previous)try{await api(`/v1/sessions/${previous.id}`,{method:'DELETE'});}catch{if(show)message('Không gửi được lệnh kết thúc. Phiên trên server có thể cần chờ hết hạn.');return;}
  pauseReason='';if(show){state('stopped');message('Đã kết thúc phiên.');}
}
$('stop').onclick=()=>stop();
setInterval(()=>{
  if(!session || !guard)return;
  if(currentInstruction && now()>=currentInstruction.deadline && !speaking){currentInstruction=null;cancelSpeech();message('Hướng dẫn đã hết hạn. Đang chờ ảnh mới.');}
  if(active && guard.expired(now()))pause('Không có ảnh mới. Hướng dẫn đã tạm dừng.');
},100);
document.addEventListener('visibilitychange',()=>{if(document.hidden && session){pause('Đã tạm dừng khi rời trang.');cameraOff();}});
window.addEventListener('pagehide',()=>{if(session)pause();cameraOff();});
if(!window.isSecureContext)message('Mở trang qua HTTPS hoặc localhost để bật camera.');
