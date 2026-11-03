#ifndef TD_SHIM_H
#define TD_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

void *td_json_client_create(void);
void td_json_client_send(void *client, const char *request);
const char *td_json_client_receive(void *client, double timeout);
const char *td_json_client_execute(void *client, const char *request);
void td_json_client_destroy(void *client);

int td_create_client_id(void);
void td_send(int client_id, const char *request);
const char *td_receive(double timeout);
const char *td_execute(const char *request);

void td_set_log_verbosity_level(int level);

#ifdef __cplusplus
}
#endif

#endif
