unit DelphiSimpleQueue;

interface
uses
  System.Generics.Collections
  , Classes
  , SyncObjs
  ;

type
  TSQTOnComplete<T> = procedure(sender: T; ASuccess: boolean; const AMsg: string) of object;
  TSQTOnNotify<T> = procedure(sender: T; const AMsg: string) of object;

  TSimpleQueueBundle = class(TObject)
  private
    FCS: TCriticalSection;
    FDict: TDictionary<string, string>;
    function GetParam(AName: string): string;
    procedure SetParam(AName: string; const Value: string);
  public
    constructor Create;
    destructor Destroy; override;
    property Param[AName: string]: string read GetParam write SetParam; default;
  end;

  TSimpleQueueTask = class
  public
    procedure Execute(AOnComplete: TSQTOnComplete<TSimpleQueueTask>; ABundle:
        TSimpleQueueBundle; AOnNotify: TSQTOnNotify<TSimpleQueueTask>); virtual; abstract;
    procedure ExecuteWrapper(AOnComplete: TSQTOnComplete<TSimpleQueueTask>;
        ABundle: TSimpleQueueBundle; AOnNotify: TSQTOnNotify<TSimpleQueueTask>); virtual;
    function Name: string; virtual;
  end;

  TSimpleQueue<T: TSimpleQueueTask> = class
  private
    FCS: TCriticalSection;
    FCurrentTask: T;
    FOnComplete: TSQTOnComplete<T>;
    FList: TList<T>;
    FOnNextTask: TNotifyEvent;
    FOnNotify: TSQTOnNotify<TSimpleQueueTask>;
    procedure ExecuteTask; virtual;
    function GetCount: Integer;
    procedure InternalExecuteTask;
    function GetNextTask: T;
    procedure OnInternalTaskComplete(sender: TSimpleQueueTask; ASuccess: boolean;
        const AMsg: string);
  protected
    FBundle: TSimpleQueueBundle;
  public
    constructor Create(AOnComplete: TSQTOnComplete<T>);
    destructor Destroy; override;
    procedure Add(ATask: T);
    procedure Clear;
    property Bundle: TSimpleQueueBundle read FBundle;
    property Count: Integer read GetCount;
    property OnNextTask: TNotifyEvent read FOnNextTask write FOnNextTask;
    property OnNotify: TSQTOnNotify<TSimpleQueueTask> read FOnNotify write
        FOnNotify;
    property OnComplete: TSQTOnComplete<T> read FOnComplete write FOnComplete;
  end;

  TSimpleQueueThreadTask = class(TSimpleQueueTask)
  public
    procedure ExecuteWrapper(AOnComplete: TSQTOnComplete<TSimpleQueueTask>;
        ABundle: TSimpleQueueBundle; AOnNotify: TSQTOnNotify<TSimpleQueueTask>); override;
  end;

  TThreadSimpleQueue<T: TSimpleQueueTask> = class(TSimpleQueue<T>)
  private
    procedure ExecuteTask; override;
  public
    constructor Create(AOnComplete: TSQTOnComplete<T>);
  end;



implementation

uses
  SysUtils
  ;

constructor TSimpleQueue<T>.Create(AOnComplete: TSQTOnComplete<T>);
begin
  inherited Create;
  FOnComplete := AOnComplete;

  FList := TList<T>.Create;
  FCS := TCriticalSection.Create;
  FBundle := TSimpleQueueBundle.Create;
end;

destructor TSimpleQueue<T>.Destroy;
begin
  FBundle.free;
  FCS.Free;
  FList.Free;
  inherited;
end;

procedure TSimpleQueue<T>.Add(ATask: T);
begin
  FCS.Enter;
  try
    FList.Add(ATask);
  finally
    FCS.Leave;
  end;
  ExecuteTask;
end;

procedure TSimpleQueue<T>.Clear;
var
  task: T;
begin
  FCS.Enter;
  try
    for task in FList do
      task.free;

    FList.Clear;

  finally
    FCS.Leave;
  end;

  if Assigned(FOnComplete) then
    FOnComplete(nil, True, 'Queue is cleared');
end;

procedure TSimpleQueue<T>.ExecuteTask;
begin
  InternalExecuteTask;
end;

function TSimpleQueue<T>.GetCount: Integer;
begin
  FCS.Enter;
  try
    Result := FList.Count;
  finally
    FCS.Leave;
  end;
end;

procedure TSimpleQueue<T>.InternalExecuteTask;
var
  task: T;
begin

  task := nil;

  FCS.Enter;
  try
    if Assigned(FCurrentTask) then
      exit;
    FCurrentTask := GetNextTask;
    task := FCurrentTask;
    if not Assigned(FCurrentTask) then
      exit;
  finally
    FCS.Leave;
  end;

  if Assigned(task) then
  begin
    if Assigned(FOnNextTask) then
      FOnNextTask(task);
    task.executeWrapper(OnInternalTaskComplete, FBundle, FOnNotify);
  end else
  begin
    if Assigned(FOnNextTask) then
      FOnNextTask(nil);
  end;



end;

function TSimpleQueue<T>.GetNextTask: T;
begin
  Result := nil;
  FCS.Enter;
  try
    if FList.Count > 0 then
    begin
      Result := FList[0];
      FList.Delete(0);
    end;
  finally
    FCs.Leave;
  end;
end;

procedure TSimpleQueue<T>.OnInternalTaskComplete(sender: TSimpleQueueTask;
    ASuccess: boolean; const AMsg: string);
begin
  if Assigned(FOnComplete) then
    FOnComplete(Sender, ASuccess, AMsg);

  Sender.Free;
  FCS.Enter;
  try
    FCurrentTask := nil;
  finally
    FCS.Leave;
  end;
  ExecuteTask;
end;

procedure TSimpleQueueTask.ExecuteWrapper(AOnComplete:
    TSQTOnComplete<TSimpleQueueTask>; ABundle: TSimpleQueueBundle; AOnNotify: TSQTOnNotify<TSimpleQueueTask>);
begin
  try
    Execute(AOnComplete, ABundle, AOnNotify);
  except
    on E: Exception do
      if Assigned(AOnComplete) then
        AOnComplete(self, False, E.message);


  end;
end;

function TSimpleQueueTask.Name: string;
begin
  Result := self.ClassName;
end;

procedure TSimpleQueueThreadTask.ExecuteWrapper(AOnComplete:
    TSQTOnComplete<TSimpleQueueTask>; ABundle: TSimpleQueueBundle; AOnNotify: TSQTOnNotify<TSimpleQueueTask>);
begin
  TThread.CreateAnonymousThread(procedure()
  begin
    Execute(AOnComplete, ABundle, AOnNotify);
  end).Start;
end;

constructor TThreadSimpleQueue<T>.Create(AOnComplete: TSQTOnComplete<T>);
begin
  inherited;

end;

procedure TThreadSimpleQueue<T>.ExecuteTask;
begin
  TThread.CreateAnonymousThread(procedure()
  begin
    InternalExecuteTask;
  end).Start;


end;

constructor TSimpleQueueBundle.Create;
begin
  FCS := TCriticalSection.Create;
  FDict := TDictionary<string,string>.Create;
end;

destructor TSimpleQueueBundle.Destroy;
begin
  FDict.Free;
  FCS.Free;
end;

function TSimpleQueueBundle.GetParam(AName: string): string;
begin
  FCS.Enter;
  try
    FDict.TryGetValue(AName, Result);
  finally
    FCS.Leave;
  end;
end;

procedure TSimpleQueueBundle.SetParam(AName: string; const Value: string);
begin
  FCS.Enter;
  try
    FDict.AddOrSetValue(AName, Value);

  finally
    FCS.Leave;
  end;
end;

end.
