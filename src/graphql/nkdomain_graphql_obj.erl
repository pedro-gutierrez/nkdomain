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

%% @doc NkDomain main module
-module(nkdomain_graphql_obj).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([execute/4]).
-export([object_schema/1]).
-export([object_query/3]).
-export([object_fields/0, object_fields_filter/1, schema_object_fields_sort/1, schema_query_all_objs/1]).

-include("nkdomain.hrl").
-include("nkdomain_graphql.hrl").
-include_lib("nkservice/include/nkservice.hrl").

%% ===================================================================
%% GraphQL Object callback
%% ===================================================================


%% @doc Called from GraphQL to extract fields on any type
execute(Ctx, Obj, Field, Args) ->
    #{nkmeta:=#{srv_id:=SrvId}} = Ctx,
    Res = ?CALL_SRV(SrvId, object_graphql_execute, [Field, Obj, Args, Ctx]),
    % lager:notice("NKLOG RES: ~p", [Res]),
    Res.



%% ===================================================================
%% Common Schema
%% ===================================================================


%% @doc Generates new scalars
-spec object_schema(scalars|enums|types|inputs|interfaces|queries|mutations) ->

    % Scalars:
    #{nkdomain_graphql:schema_type() => #{comment => string()}} |

    % Enums:
    #{nkdomain_graphql:schema_type() => #{opts => [atom()], comment => string()}} |

    % Types
    #{
        nkdomain_graphql:schema_type() => #{
            fields => nkdomain_graphql:schema_fields(),
            comment => string(),
            is_object => boolean(),         % Generates an Object instance
            is_connection => boolean()      % Generates specific connection types
        }
    } |

    % Inputs:
    #{
        nkdomain_graphql:schema_type() => #{
            fields => nkdomain_graphql:schema_fields(),
            comment => string()
        }
    } |

    % Interfaces
    #{
        nkdomain_graphql:schema_type() => #{
            fields => nkdomain_graphql:schema_fields(),
            comment => string()
            }
    } |

    % Queries
    #{nkdomain_graphql:query_name() => nkdomain_graphql:field_value()} |

    % Mutations
    #{
        nkdomain_graphql:mutation_name() => #{
            inputs => nkdomain_graphql:schema_fields(),
            outputs => nkdomain_graphql:schema_fields(),
            comment => string()
        }
    }.

object_schema(scalars) ->
    #{
        'Cursor' => #{comment=>"Pagination cursor"},
        'UnixTime' => #{comment=>"Standard milisecond-resolution unix time"}
    };

object_schema(enums) ->
    #{
        objectType => #{
            opts => nkdomain_reg:get_all_schema_types(),
            comment => "Object Types"
        },
        filterOp => #{
            opts => ['AND', 'OR', 'NOT'],
            comment => "Operation mode for a filter"
        },
        sortOrder => #{
            opts => ['ASC', 'DESC']
        }
    };

object_schema(types) ->
    #{
        'SearchResult' => #{
            fields => #{
                objects => {list_no_null, 'Object', #{comment => "My Objects"}},
                pageInfo => {no_null, 'PageInfo'},
                totalCount => int
            }
        },
        'PageInfo' => #{
            fields => #{
                hasNextPage => {no_null, boolean},
                hasPreviousPage => {no_null, boolean}
            }
        }
    };

object_schema(inputs) ->
    #{
        objectFilterId => #{
            fields => #{
                eq => string,
                values => {list, string},
                exists => bool
            }
        },
        objectFilterType => #{
            fields => #{
                eq => objectType,
                values => {list, objectType}
            }
        },
        objectFilterKeyword => #{
            fields => #{
                eq => string,
                values => {list, string},
                gt => string,
                gte => string,
                lt => string,
                lte => string,
                prefix => string,
                exists => bool
            }
        },
        objectFilterNorm => #{
            fields => #{
                eq => string,
                prefix => string,
                wordsAndPrefix => string,
                fuzzy => string
            }
        },
        objectFilterPath => #{
            fields => #{
                eq => string,
                values => {list, string},
                gt => string,
                gte => string,
                lt => string,
                lte => string,
                childsOf => string,
                exists => bool
            }
        },
        objectFilterInt => #{
            fields => #{
                values => {list, int},
                eq => int,
                ne => int,
                gt => int,
                gte => int,
                lt => int,
                lte => int,
                exists => bool
            }
        },
        objectFilterBoolean => #{
            fields => #{
                eq => boolean,
                exists => bool
            }
        },
        objectFilter => #{
            fields => object_fields_filter(#{}),
            comment => "Filter values to sort on"
        },
        objectSortField => #{
            fields => #{
                order => {sortOrder, #{default => <<"ASC">>}}
            }
        },
        objectSort => #{
            fields => schema_object_fields_sort([]),
            comment => "Fields to sort on"
        }
    };

object_schema(interfaces) ->
    #{
        'Node' => #{
            fields => #{id => {no_null, id}},
            comment => "Relay Modern Node Interface"
        },
        'Object'=> #{
            fields => object_fields(),
            comment => "Standard NetComposer Object"
        }
    };

object_schema(queries) ->
    #{
        node => {'Node', #{
                     params => #{id => {no_null, id}},
                     comment => "Relay Modern specification Node fetcher"
                 }},
        allObjects => schema_query_all_objs(<<>>)
    };

object_schema(_) ->
    #{
    }.



%% ===================================================================
%% Queries implementations
%% ===================================================================

%% @doc
object_query(<<"node">>, #{<<"id">>:=Id}, _Ctx) ->
    case nkdomain_lib:read(Id) of
        {ok, #obj_id_ext{}=ObjIdExt, Obj} ->
            {ok, {ObjIdExt, Obj}};
        {error, Error} ->
            {error, Error}
    end;

object_query(<<"allObjects">>, Params, Ctx) ->
    nkdomain_graphql_util:search(Params, Ctx).


%% ===================================================================
%% Queries execute
%% ===================================================================



%% ===================================================================
%% Internal
%% ===================================================================


%% @private
object_fields() ->
    #{
        % aliases => {list, string, #{comment => "List of object aliases"}},
        createdBy => {no_null, 'User', #{comment => "User that created the object"}},
        createdById => {no_null, string, #{comment => "UserId that created the object"}},
        createdTime => {no_null, time, #{comment => "Object creation time"}},
        description => {string, #{comment => "User-related description"}},
        destroyed => {boolean, #{comment => "True if the object is destroyed"}},
        destroyedCode => {string, #{comment => "Destruction reason code"}},
        destroyedReason => {string, #{comment => "Destruction reason text"}},
        destroyedTime => {time, #{comment => "Destruction time"}},
        domain => {no_null, 'Domain', #{comment => "Domain this object belongs to"}},
        domainId => {no_null, string, #{comment => "DomainId this object belongs to"}},
        enabled => {no_null, boolean, #{comment => "False if object is disabled"}},
        expiresTime => {time, #{comment => "Time this object will expire"}},
        icon => {'File', #{comment => "Object File icon"}},
        iconId => {string, #{comment => "Object FileId icon"}},
        id => {no_null, id, #{comment=>"Main ID fetcher"}},
        name => {string, #{comment => "Object's user-related name"}},
        objId => {no_null, string, #{comment => "Object's ID"}},
        objName => {no_null, string, #{comment => "Object's short name"}},
        path => {no_null, string, #{comment => "Object's directory path"}},
        srvId => {string, #{comment => "Object's service"}},
        % subtypes => {list, string, #{comment => "Object's subtypes"}},
        % tags => {list, string, #{comment => "Object's tags"}},
        type => {no_null, objectType, #{comment => "Object's type"}},
        updatedBy => {no_null, 'User', #{comment => "User that updated the object"}},
        updatedById => {no_null, string, #{comment => "UserId that updated the object"}},
        updatedTime => {no_null, time, #{comment => "Object updation time"}},
        vsn => {string, #{comment => "Object's current version"}}
    }.


%% @private
object_fields_filter(Fields) ->
    Base = #{
        op => {filterOp, #{comment => "Operation Type"}},
        % aliases => {objectFilterKeyword, #{comment => "Object has an alias"}},
        createdById => {objectFilterId, #{comment => "Objects created by this user"}},
        createdTime => {objectFilterInt, #{comment => "Object creation time"}},
        description => {objectFilterNorm, #{comment => "Words in description"}},
        destroyed => {objectFilterBoolean, #{comment => "Filter by destroyed objects"}},
        destroyedTime => {objectFilterInt, #{comment => "Destruction time"}},
        domainId => {objectFilterId, #{comment => "Filter objects belonging to this domain"}},
        enabled => {objectFilterBoolean, #{comment => "Filter enabled or disabled objects"}},
        expiresTime => {objectFilterInt, #{comment => "Time this object will expire"}},
        iconId => {objectFilterId, #{comment => "Objects hanving this iconId"}},
        name => {objectFilterNorm, #{comment => "Words in name"}},
        objId => {objectFilterId, #{comment => "Object's ID"}},
        objName => {objectFilterKeyword, #{comment => "Object's with this short name"}},
        path => {objectFilterPath, #{comment => "Filter on this path"}},
        srvId => {objectFilterId, #{comment => "Object's service"}},
        % subTypes => {list, objectFilterId, #{comment => "Object's subtypes"}},
        % tags => {list, objectFilterId, #{comment => "Object's tags"}},
        type => {objectFilterType, #{comment => "Object's type"}},
        updatedById => {objectFilterId, #{comment => "User that updated the object"}},
        updatedTime => {objectFilterInt, #{comment => "Object updation time"}},
        vsn => {objectFilterKeyword, #{comment => "Object's current version"}}
    },
    maps:merge(Base, Fields).


%% @private
schema_object_fields_sort(Fields) ->
    Base = [domainId, createdById, createdTime, enabled, expiresTime, objName, path, srvId],
    List = [{Field, objectSortField} || Field <- lists:usort(Base++Fields)],
    maps:from_list(List).


%% @private
%% Object must define 'TypeSearchResult', 'objectTypeFilter' and 'objectTypeSort'
schema_query_all_objs(Type) ->
    Type2 = to_bin(Type),
    Result = binary_to_atom(<<Type2/binary, "SearchResult">>, latin1),
    Filter = binary_to_atom(<<"object", Type2/binary, "Filter">>, latin1),
    Sort = binary_to_atom(<<"object", Type2/binary, "Sort">>, latin1),
    {Result, #{
        params => #{
            filter => {list, Filter, #{default => "[]"}},
            sort => {list, Sort, #{default => "[]"}},
            from => {int, #{default => 0}},
            size => {int, #{default => 10}}
    }}}.



%% @private
to_bin(T) when is_binary(T)-> T;
to_bin(T) -> nklib_util:to_binary(T).


