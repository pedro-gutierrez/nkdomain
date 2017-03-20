%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Carlos Gonzalez Florido.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------


%% @doc Basic Obj utilities


-module(nkdomain_obj_lib).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([find/2, load/2, load/3, create/3]).
-export([do_find/1, do_call/2, do_call/3, do_cast/2, do_info/2]).

%%-include("nkdomain.hrl").

-define(DEF_SYNC_CALL, 5000).

%% ===================================================================
%% Public
%% ===================================================================

%% @doc Finds and object from UUID or Path, in memory and disk
-spec find(nkservice:id(), nkdomain:obj_id()|nkdomain:path()) ->
    {ok, nkdomain:type(), domain:obj_id(), nkdomain:path(), pid()|undefined} |
    {error, object_not_found|term()}.

find(Srv, IdOrPath) ->
    case nkdomain_util:is_path(IdOrPath) of
        {true, Path} ->
            case nkservice_srv:get_srv_id(Srv) of
                {ok, SrvId} ->
                    case SrvId:object_store_find_path(SrvId, Path) of
                        {ok, Type, ObjId} ->
                            case do_find(ObjId) of
                                {ok, Type, ObjId, Path, Pid} ->
                                    {ok, Type, ObjId, Path, Pid};
                                not_found ->
                                    {ok, Type, ObjId, Path, undefined}
                            end;
                        {error, Error} ->
                            {error, Error}
                    end;
                not_found ->
                    {error, service_not_found}
            end;
        false ->
            ObjId = nklib_util:to_binary(IdOrPath),
            case do_find(ObjId) of
                {ok, Type, ObjId, Path, Pid} ->
                    {ok, Type, ObjId, Path, Pid};
                not_found ->
                    case nkservice_srv:get_srv_id(Srv) of
                        {ok, SrvId} ->
                            case SrvId:object_store_find_obj_id(SrvId, ObjId) of
                                {ok, Type, Path} ->
                                    {ok, Type, ObjId, Path, undefined};
                                {error, Error} ->
                                    {error, Error}
                            end;
                        not_found ->
                            {error, service_not_found}
                    end
            end
    end.


%% @doc Finds an objects's pid or loads it from storage
-spec load(nkservice:id(), nkdomain:obj_id()|nkdomain:path()) ->
    {ok, nkdomain:type(), nkdomain:obj_id(), pid()} |
    {error, obj_not_found|term()}.

load(Srv, IdOrPath) ->
    load(Srv, IdOrPath, #{}).


%% @doc Finds an objects's pid or loads it from storage
-spec load(nkservice:id(), nkdomain:obj_id()|nkdomain:path(), nkdomain_obj:load_opts()) ->
    {ok, nkdomain:type(), nkdomain:obj_id(), pid()} |
    {error, obj_not_found|term()}.

load(Srv, IdOrPath, Meta) ->
    case find(Srv, IdOrPath) of
        {ok, Type, ObjId, _Path, Pid} when is_pid(Pid) ->
            case Meta of
                #{register:=Link} ->
                    register(Pid, Link);
                _ ->
                    ok
            end,
            {ok, Type, ObjId, Pid};
        {ok, _Type, ObjId, _Path, undefined} ->
            do_load2(Srv, ObjId, Meta);
        {error, object_not_found} ->
            ObjId = nklib_util:to_binary(IdOrPath),
            do_load2(Srv, ObjId, Meta)
    end.


%% @private
do_load2(Srv, ObjId, Meta) ->
    case nkservice_srv:get_srv_id(Srv) of
        {ok, SrvId} ->
            Meta2 = Meta#{
                srv_id => SrvId,
                is_dirty => false
            },
            case SrvId:object_load(SrvId, ObjId) of
                {ok, _Module, Obj} ->
                    case Obj of
                        #{expires_time:=Expires} ->
                            case nklib_util:m_timestamp() of
                                Now when Now >= Expires ->
                                    SrvId:object_store_remove_raw(SrvId, ObjId),
                                    {error, object_not_found};
                                _ ->
                                    do_load3(ObjId, Obj, Meta2)
                            end;
                        _ ->
                            do_load3(ObjId, Obj, Meta2)
                    end;
                {error, Error} ->
                    {error, Error}
            end
    end.


%% @private
do_load3(ObjId, #{type:=Type}=Obj, Meta2) ->
    {ok, ObjPid} = nkdomain_obj:start(Obj, Meta2),
    {ok, Type, ObjId, ObjPid}.


%% @doc Creates a new object
-spec create(nkservice:id(), map(), nkdomain_obj:create_opts()) ->
    {ok, nkdomain:obj_id(), pid()}.

create(_Srv, #{obj_id:=_}, _Meta) ->
    {error, invalid_object_id};

create(_Srv, #{<<"obj_id">>:=_}, _Meta) ->
    {error, invalid_object_id};

create(Srv, Obj, Meta) ->
    case nkservice_srv:get_srv_id(Srv) of
        {ok, SrvId} ->
            case Meta of
                #{obj_id:=ObjId} ->
                    case load(Srv, ObjId, #{}) of                       % TODO: Use some usage?
                        {ok, _Type, _ObjId, _Pid} ->
                            {error, object_already_exists};
                        {error, object_not_found} ->
                            do_create(SrvId, Obj#{obj_id=>ObjId}, Meta);
                        {error, Error} ->
                            {error, Error}
                    end;
                _ ->
                    Type = case Obj of
                        #{type:=ObjType} -> ObjType;
                        #{<<"type">>:=ObjType} -> ObjType
                    end,
                    {ObjId, _Meta2} = nkmedia_util:add_id(obj_id, Meta, Type),
                    do_create(SrvId, Obj#{obj_id=>ObjId}, Meta)
            end;
        not_found ->
            {error, service_not_found}
    end.


%% @private
do_create(SrvId, Obj, Meta) ->
    Type = case Obj of
        #{type:=ObjType} -> ObjType;
        #{<<"type">>:=ObjType} -> ObjType
    end,
    case SrvId:object_parse(SrvId, load, Type, Obj) of
        {ok, _Module, #{obj_id:=ObjId}=Obj2} ->
            % We know type is valid here
            Obj3 = Obj2#{
                created_time => nklib_util:m_timestamp()
            },
            case do_create_check_parent(SrvId, Obj3) of
                {ok, Obj4, ParentMeta} ->
                    Meta2 = Meta#{
                        srv_id => SrvId,
                        is_dirty => true
                    },
                    Meta3 = maps:merge(Meta2, ParentMeta),
                    {ok, ObjPid} = nkdomain_obj:start(Obj4, Meta3),
                    {ok, ObjId, ObjPid};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @private
do_create_check_parent(_SrvId, #{parent_id:=<<>>, type:=<<"domain">>, obj_id:=<<"root">>}=Obj) ->
    {ok, Obj, #{}};

do_create_check_parent(SrvId, #{parent_id:=ParentId, type:=Type, path:=Path}=Obj) ->
    case load(SrvId, ParentId, #{}) of                                      % TODO: Use some usage?
        {ok, _ParentType, ParentId, Pid} ->
            case do_call(Pid, {nkdomain_check_child, Type, Path}) of
                {ok, Data} ->
                    {ok, Obj, Data};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            lager:notice("Error loading parent object ~s (~p)", [ParentId, Error]),
            {error, could_not_load_parent}
    end;

do_create_check_parent(SrvId, #{type:=Type, path:=Path}=Obj) ->
    lager:error("BB ~p ~p", [Type, Path]),
    case nkdomain_util:get_parts(Type, Path) of
        {ok, Base, _Name} ->
            lager:error("BASE IS ~p", [Base]),
            case find(SrvId, Base) of
                {ok, _ParentType, ParentId, _ParentPath, _Pid} ->
                    lager:error("PARENT IS ~p", [ParentId]),
                    do_create_check_parent(SrvId, Obj#{parent_id=>ParentId});
                {error, _} ->
                    {error, could_not_load_parent}
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @private
do_find({Srv, Path}) ->
    case nkservice_srv:get_srv_id(Srv) of
        {ok, SrvId} ->
            case SrvId:object_store_find_path(SrvId, Path) of
                {ok, _Type, ObjId} when is_binary(ObjId) ->
                    do_find(ObjId);
                _ ->
                    not_found
            end;
        not_found ->
            not_found
    end;



do_find(ObjId) when is_binary(ObjId) ->
    case nklib_proc:values({nkdomain_obj, ObjId}) of
        [{{Type, Path}, Pid}] ->
            {ok, Type, ObjId, Path, Pid};
        [] ->
            not_found
    end;

do_find(ObjId) ->
    do_find(nklib_util:to_binary(ObjId)).


%% @private
do_call(Id, Msg) ->
    do_call(Id, Msg, ?DEF_SYNC_CALL).


%% @private
do_call(Pid, Msg, Timeout) when is_pid(Pid) ->
    nkservice_util:call(Pid, Msg, Timeout);

do_call(Id, Msg, Timeout) ->
    case do_find(Id) of
        {ok, _Type, _ObjId, _Path, Pid} when is_pid(Pid) ->
            do_call(Pid, Msg, Timeout);
        not_found ->
            {error, obj_not_found}
    end.


%% @private
do_cast(Pid, Msg) when is_pid(Pid) ->
    gen_server:cast(Pid, Msg);

do_cast(Id, Msg) ->
    case do_find(Id) of
        {ok, _Type, _ObjId, _Path, Pid} when is_pid(Pid) ->
            do_cast(Pid, Msg);
        not_found ->
            {error, obj_not_found}
    end.


%% @private
do_info(Pid, Msg) when is_pid(Pid) ->
    Pid ! Msg;

do_info(Id, Msg) ->
    case do_find(Id) of
        {ok, _Type, _ObjId, _Path, Pid} when is_pid(Pid) ->
            do_info(Pid, Msg);
        not_found ->
            {error, obj_not_found}
    end.
