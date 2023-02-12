// SPDX-FileCopyrightText: © 2022 Svix Authors
// SPDX-License-Identifier: MIT

use crate::{
    core::{
        permissions,
        types::{EventTypeName, FeatureFlag},
    },
    ctx,
    db::models::eventtype,
    error::{HttpError, Result},
    v1::utils::{
        api_not_implemented, openapi_desc, openapi_tag,
        patch::{
            patch_field_non_nullable, patch_field_nullable, UnrequiredField,
            UnrequiredNullableField,
        },
        validate_no_control_characters, validate_no_control_characters_unrequired, EmptyResponse,
        EventTypeNamePath, ListResponse, ModelIn, ModelOut, Pagination, PaginationLimit,
        ValidatedJson, ValidatedQuery,
    },
    AppState,
};
use aide::axum::{
    routing::{get_with, post_with},
    ApiRouter,
};
use axum::{
    extract::{Path, State},
    Json,
};
use chrono::{DateTime, Utc};
use hyper::StatusCode;
use schemars::JsonSchema;
use sea_orm::{entity::prelude::*, ActiveValue::Set, QueryOrder};
use sea_orm::{ActiveModelTrait, QuerySelect};
use serde::{Deserialize, Serialize};
use server_derive::{ModelIn, ModelOut};
use validator::Validate;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, Validate, ModelIn, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct EventTypeIn {
    pub name: EventTypeName,
    #[validate(custom = "validate_no_control_characters")]
    pub description: String,
    #[serde(default, rename = "archived")]
    pub deleted: bool,
    pub schemas: Option<eventtype::Schema>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub feature_flag: Option<FeatureFlag>,
}

// FIXME: This can and should be a derive macro
impl ModelIn for EventTypeIn {
    type ActiveModel = eventtype::ActiveModel;

    fn update_model(self, model: &mut Self::ActiveModel) {
        let EventTypeIn {
            name,
            description,
            deleted,
            schemas,
            feature_flag,
        } = self;

        model.name = Set(name);
        model.description = Set(description);
        model.deleted = Set(deleted);
        model.schemas = Set(schemas);
        model.feature_flag = Set(feature_flag);
    }
}

#[derive(Clone, Debug, PartialEq, Deserialize, Validate, ModelIn, JsonSchema)]
#[serde(rename_all = "camelCase")]
struct EventTypeUpdate {
    #[validate(custom = "validate_no_control_characters")]
    description: String,
    #[serde(default, rename = "archived")]
    deleted: bool,
    schemas: Option<eventtype::Schema>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    feature_flag: Option<FeatureFlag>,
}

// FIXME: This can and should be a derive macro
impl ModelIn for EventTypeUpdate {
    type ActiveModel = eventtype::ActiveModel;

    fn update_model(self, model: &mut Self::ActiveModel) {
        let EventTypeUpdate {
            description,
            deleted,
            schemas,
            feature_flag,
        } = self;

        model.description = Set(description);
        model.deleted = Set(deleted);
        model.schemas = Set(schemas);
        model.feature_flag = Set(feature_flag);
    }
}

#[derive(Deserialize, ModelIn, Serialize, Validate, JsonSchema)]
#[serde(rename_all = "camelCase")]
struct EventTypePatch {
    #[serde(default, skip_serializing_if = "UnrequiredField::is_absent")]
    #[validate(custom = "validate_no_control_characters_unrequired")]
    description: UnrequiredField<String>,

    #[serde(
        default,
        rename = "archived",
        skip_serializing_if = "UnrequiredField::is_absent"
    )]
    deleted: UnrequiredField<bool>,

    #[serde(default, skip_serializing_if = "UnrequiredNullableField::is_absent")]
    schemas: UnrequiredNullableField<eventtype::Schema>,

    #[serde(default, skip_serializing_if = "UnrequiredNullableField::is_absent")]
    feature_flag: UnrequiredNullableField<FeatureFlag>,
}

impl ModelIn for EventTypePatch {
    type ActiveModel = eventtype::ActiveModel;

    fn update_model(self, model: &mut Self::ActiveModel) {
        let EventTypePatch {
            description,
            deleted,
            schemas,
            feature_flag,
        } = self;

        patch_field_non_nullable!(model, description);
        patch_field_non_nullable!(model, deleted);
        patch_field_nullable!(model, schemas);
        patch_field_nullable!(model, feature_flag);
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, ModelOut, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct EventTypeOut {
    pub name: EventTypeName,
    pub description: String,
    #[serde(rename = "archived")]
    pub deleted: bool,
    pub schemas: Option<eventtype::Schema>,

    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub feature_flag: Option<FeatureFlag>,
}

impl EventTypeOut {
    fn without_payload(model: eventtype::Model) -> Self {
        Self {
            schemas: None,
            ..model.into()
        }
    }
}

// FIXME: This can and should be a derive macro
impl From<eventtype::Model> for EventTypeOut {
    fn from(model: eventtype::Model) -> Self {
        Self {
            name: model.name,
            description: model.description,
            deleted: model.deleted,
            schemas: model.schemas,
            feature_flag: model.feature_flag,

            created_at: model.created_at.into(),
            updated_at: model.updated_at.into(),
        }
    }
}

#[derive(Debug, Deserialize, Validate, JsonSchema)]
pub struct ListFetchOptions {
    #[serde(default)]
    pub include_archived: bool,
    #[serde(default)]
    pub with_content: bool,
}

const LIST_EVENT_TYPES_DESCRIPTION: &str = "Return the list of event types.";

async fn list_event_types(
    State(AppState { ref db, .. }): State<AppState>,
    pagination: ValidatedQuery<Pagination<EventTypeName>>,
    fetch_options: ValidatedQuery<ListFetchOptions>,
    permissions::ReadAll {
        org_id,
        feature_flags,
        ..
    }: permissions::ReadAll,
) -> Result<Json<ListResponse<EventTypeOut>>> {
    let PaginationLimit(limit) = pagination.limit;
    let iterator = pagination.iterator.clone();

    let mut query = eventtype::Entity::secure_find(org_id)
        .order_by_asc(eventtype::Column::Name)
        .limit(limit + 1);

    if !fetch_options.include_archived {
        query = query.filter(eventtype::Column::Deleted.eq(false));
    }

    if let Some(iterator) = iterator {
        query = query.filter(eventtype::Column::Name.gt(iterator));
    }

    if let permissions::AllowedFeatureFlags::Some(flags) = feature_flags {
        query = eventtype::Entity::filter_feature_flags(query, flags);
    }

    Ok(Json(EventTypeOut::list_response_no_prev(
        ctx!(query.all(db).await)?
            .into_iter()
            .map(|x| {
                if !fetch_options.with_content {
                    EventTypeOut::without_payload(x)
                } else {
                    x.into()
                }
            })
            .collect(),
        limit as usize,
    )))
}

const CREATE_EVENT_TYPE_DESCRIPTION: &str = r#"
Create new or unarchive existing event type.

Unarchiving an event type will allow endpoints to filter on it and messages to be sent with it.
Endpoints filtering on the event type before archival will continue to filter on it.
This operation does not preserve the description and schemas.
"#;

async fn create_event_type(
    State(AppState { ref db, .. }): State<AppState>,
    permissions::Organization { org_id }: permissions::Organization,
    ValidatedJson(data): ValidatedJson<EventTypeIn>,
) -> Result<(StatusCode, Json<EventTypeOut>)> {
    let evtype = ctx!(
        eventtype::Entity::secure_find_by_name(org_id.clone(), data.name.to_owned())
            .one(db)
            .await
    )?;
    let ret = match evtype {
        Some(evtype) => {
            if evtype.deleted {
                let mut evtype: eventtype::ActiveModel = evtype.into();
                evtype.deleted = Set(false);
                data.update_model(&mut evtype);
                ctx!(evtype.update(db).await)?
            } else {
                return Err(HttpError::conflict(
                    Some("event_type_exists".to_owned()),
                    Some("An event_type with this name already exists".to_owned()),
                )
                .into());
            }
        }
        None => {
            let evtype = eventtype::ActiveModel {
                org_id: Set(org_id),
                ..data.into()
            };
            ctx!(evtype.insert(db).await)?
        }
    };
    Ok((StatusCode::CREATED, Json(ret.into())))
}

const GET_EVENT_TYPE_DESCRIPTION: &str = "Get an event type.";

async fn get_event_type(
    State(AppState { ref db, .. }): State<AppState>,
    Path(EventTypeNamePath { event_type_name }): Path<EventTypeNamePath>,
    permissions::ReadAll {
        org_id,
        feature_flags,
        ..
    }: permissions::ReadAll,
) -> Result<Json<EventTypeOut>> {
    let mut query = eventtype::Entity::secure_find_by_name(org_id, event_type_name);
    if let permissions::AllowedFeatureFlags::Some(flags) = feature_flags {
        query = eventtype::Entity::filter_feature_flags(query, flags);
    }
    let evtype = ctx!(query.one(db).await)?.ok_or_else(|| HttpError::not_found(None, None))?;

    Ok(Json(evtype.into()))
}

const UPDATE_EVENT_TYPE_DESCRIPTION: &str = "Update an event type.";

async fn update_event_type(
    State(AppState { ref db, .. }): State<AppState>,
    Path(EventTypeNamePath { event_type_name }): Path<EventTypeNamePath>,
    permissions::Organization { org_id }: permissions::Organization,
    ValidatedJson(data): ValidatedJson<EventTypeUpdate>,
) -> Result<(StatusCode, Json<EventTypeOut>)> {
    let evtype = ctx!(
        eventtype::Entity::secure_find_by_name(org_id.clone(), event_type_name.clone())
            .one(db)
            .await
    )?;

    match evtype {
        Some(evtype) => {
            let mut evtype: eventtype::ActiveModel = evtype.into();
            data.update_model(&mut evtype);
            let ret = ctx!(evtype.update(db).await)?;

            Ok((StatusCode::OK, Json(ret.into())))
        }
        None => {
            let ret = ctx!(
                eventtype::ActiveModel {
                    org_id: Set(org_id),
                    name: Set(event_type_name),
                    ..data.into()
                }
                .insert(db)
                .await
            )?;

            Ok((StatusCode::CREATED, Json(ret.into())))
        }
    }
}

const PATCH_EVENT_TYPE_DESCRIPTION: &str = "Partially update an event type.";

async fn patch_event_type(
    State(AppState { ref db, .. }): State<AppState>,
    Path(EventTypeNamePath { event_type_name }): Path<EventTypeNamePath>,
    permissions::Organization { org_id }: permissions::Organization,
    ValidatedJson(data): ValidatedJson<EventTypePatch>,
) -> Result<Json<EventTypeOut>> {
    let evtype = ctx!(
        eventtype::Entity::secure_find_by_name(org_id, event_type_name)
            .one(db)
            .await
    )?
    .ok_or_else(|| HttpError::not_found(None, None))?;

    let mut evtype: eventtype::ActiveModel = evtype.into();
    data.update_model(&mut evtype);

    let ret = ctx!(evtype.update(db).await)?;
    Ok(Json(ret.into()))
}

const DELETE_EVENT_TYPE_DESCRIPTION: &str = r#"
Archive an event type.

Endpoints already configured to filter on an event type will continue to do so after archival.
However, new messages can not be sent with it and endpoints can not filter on it.
An event type can be unarchived with the
[create operation](#operation/create_event_type_api_v1_event_type__post).
"#;

async fn delete_event_type(
    State(AppState { ref db, .. }): State<AppState>,
    Path(EventTypeNamePath { event_type_name }): Path<EventTypeNamePath>,
    permissions::Organization { org_id }: permissions::Organization,
) -> Result<(StatusCode, Json<EmptyResponse>)> {
    let evtype = ctx!(
        eventtype::Entity::secure_find_by_name(org_id, event_type_name)
            .one(db)
            .await
    )?
    .ok_or_else(|| HttpError::not_found(None, None))?;

    let mut evtype: eventtype::ActiveModel = evtype.into();
    evtype.deleted = Set(true);
    ctx!(evtype.update(db).await)?;
    Ok((StatusCode::NO_CONTENT, Json(EmptyResponse {})))
}

const GENERATE_SCHEMA_EXAMPLE_DESCRIPTION: &str =
    "Generates a fake example from the given JSONSchema";

pub fn router() -> ApiRouter<AppState> {
    let tag = openapi_tag("Event Type");
    ApiRouter::new()
        .api_route_with(
            "/event-type/",
            post_with(
                create_event_type,
                openapi_desc(CREATE_EVENT_TYPE_DESCRIPTION),
            )
            .get_with(list_event_types, openapi_desc(LIST_EVENT_TYPES_DESCRIPTION)),
            &tag,
        )
        .api_route_with(
            "/event-type/:event_type_name/",
            get_with(get_event_type, openapi_desc(GET_EVENT_TYPE_DESCRIPTION))
                .put_with(
                    update_event_type,
                    openapi_desc(UPDATE_EVENT_TYPE_DESCRIPTION),
                )
                .patch_with(patch_event_type, openapi_desc(PATCH_EVENT_TYPE_DESCRIPTION))
                .delete_with(
                    delete_event_type,
                    openapi_desc(DELETE_EVENT_TYPE_DESCRIPTION),
                ),
            &tag,
        )
        .api_route_with(
            "/event-type/schema/generate-example/",
            post_with(
                api_not_implemented,
                openapi_desc(GENERATE_SCHEMA_EXAMPLE_DESCRIPTION),
            ),
            tag,
        )
}

#[cfg(test)]
mod tests {

    use super::ListFetchOptions;
    use serde_json::json;

    #[test]
    fn test_list_fetch_options_default() {
        let l: ListFetchOptions = serde_json::from_value(json!({})).unwrap();
        assert!(!l.include_archived);
        assert!(!l.with_content);
    }
}