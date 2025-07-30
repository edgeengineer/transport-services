//
//  CIOUring.h
//  
//
//  Maximilian Alexander
//

#ifndef CIOUring_h
#define CIOUring_h

#include <liburing.h>

struct io_uring_handle {
    struct io_uring ring;
};

struct io_uring_handle* iouring_create(unsigned entries);
void iouring_destroy(struct io_uring_handle* handle);
int iouring_submit_and_wait(struct io_uring_handle* handle, unsigned wait_nr);
struct io_uring_sqe* iouring_get_sqe(struct io_uring_handle* handle);
void iouring_cqe_seen(struct io_uring_handle* handle, struct io_uring_cqe* cqe);

#endif /* CIOUring_h */
