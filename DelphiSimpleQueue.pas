unit DelphiSimpleQueue;

interface
uses
  System.Generics.Collections
  , Classes
  , SyncObjs
  ;

type
  TSQTOnComplete<T> = procedure(sender: T; ASuccess: boolean; const AMsg: string) of object;

  TSimpleQueueTask = class
  public
    procedure execute(AOnComplete: TSQTOnComplete<TSimpleQueueTask>); virtual; abstract;
  end;

  TSimpleQueue<T: TSimpleQueueTask> = class
  private
    FCS: TCriticalSection;
    FCurrentTask: T;
    FOnComplete: TSQTOnComplete<T>;
    FList: TList<T>;
    procedure ExecuteTask;
    function GetNextTask: T;
    procedure OnInternalTaskComplete(sender: TSimpleQueueTask; ASuccess: boolean;
        const AMsg: string);
  public
    constructor Create(AOnComplete: TSQTOnComplete<T>);
    destructor Destroy; override;
    procedure Add(ATask: T);
    property OnComplete: TSQTOnComplete<T> read FOnComplete write FOnComplete;
  end;

implementation

constructor TSimpleQueue<T>.Create(AOnComplete: TSQTOnComplete<T>);
begin
  inherited Create;
  FOnComplete := AOnComplete;

  FList := TList<T>.Create;
  FCS := TCriticalSection.Create;
end;

destructor TSimpleQueue<T>.Destroy;
begin
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

procedure TSimpleQueue<T>.ExecuteTask;
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
    task.execute(OnInternalTaskComplete);



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

end.
