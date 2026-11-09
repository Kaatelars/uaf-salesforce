/**
 * @description Exception thrown by the UAF trigger framework for configuration or usage errors
 *              (missing dispatcher, invalid dispatcher type, invalid trigger context).
 *              Sharing: {@code inherited sharing} so framework code always runs in the sharing
 *              context of its caller (trigger, handler or Flow) and never widens it.
 * @group UAF Core
 */
public inherited sharing class UAF_TriggerException extends Exception {}
