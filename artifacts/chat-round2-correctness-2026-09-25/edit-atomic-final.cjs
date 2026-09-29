const fs=require('fs');
const p='lib/src/services/im/im05_persistence.dart'; let s=fs.readFileSync(p,'utf8');
function replace(a,b){if(!s.includes(a))throw Error(a);s=s.replace(a,b)}
replace('return changed ? persisted : null;',`return changed ? await transaction.findOutbox(
        ownerUserId: next.ownerUserId, operationId: next.operationId) : null;`);
const begin=s.indexOf('      if (draftAcceptance != null) {'); const end=s.indexOf('\n    });',begin);
const block=s.slice(begin,end), accept=block.slice(0,block.indexOf('      return _assess('));
const assess=block.slice(block.indexOf('      return _assess(')).replace('return _assess','final assessment = _assess');
s=s.slice(0,begin)+assess+'\n'+accept.replace('if (draftAcceptance != null)','if (draftAcceptance != null && assessment.canDispatch)')+'      return assessment;'+s.slice(end);
replace('      return mainChanged && copyChanged;',`      if (!mainChanged || !copyChanged) throw StateError('outcome transition lost conditional update');
      return true;`);
for(const name of ['markPreparedOutboxManualRequired','abandonOutcomeUnknown','completeOutboxProjection']){
 const a=s.indexOf('  Future<bool> '+name+'('), b=s.indexOf('\n  Future<',a+1); let chunk=s.slice(a,b);
 chunk=chunk.replace('if (!copyChanged) return false;',"if (!copyChanged) throw StateError('recovery transition lost conditional update');");
 chunk=chunk.replace('return transaction.updateOutboxIfCurrent(','final mainChanged = await transaction.updateOutboxIfCurrent(');
 const pos=chunk.lastIndexOf('    });'); chunk=chunk.slice(0,pos)+"      if (!mainChanged) throw StateError('main transition lost conditional update');\n      return true;\n"+chunk.slice(pos);
 s=s.slice(0,a)+chunk+s.slice(b);
}
fs.writeFileSync(p,s);
