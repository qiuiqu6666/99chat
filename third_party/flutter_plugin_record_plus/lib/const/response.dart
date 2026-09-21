class RecordResponse {
  bool? success;
  String? path;
  String? msg;
  String? key;
  String? sessionId;
  double? audioTimeLength;

  RecordResponse(
      {this.success,
      this.path,
      this.msg,
      this.key,
      this.sessionId,
      this.audioTimeLength});
//  RecordResponse({this.success, this.path,this.msg,this.key});
}
