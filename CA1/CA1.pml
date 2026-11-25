mtype = {
    EXECUTE,
    ROLLBACK,
    TERMINATE,
    SUCCESS,
    FAILURE,
    ACK
};

/* channels: one between each service and coordinator */
chan inv_channel = [0] of { mtype };
chan pay_channel = [0] of { mtype };
chan ship_channel = [0] of { mtype };

/* true only when inventory, payment, and shipping all succeed. */
bool transaction_completed = false;

/* terminaes a service after completing all the steps */
inline terminate_service(ch)
{
    ch!TERMINATE;
    ch?ACK
}

inline compensate_service(ch, response) {
	ch!ROLLBACK;
	ch?response;
	assert(response == SUCCESS)
}

inline rollback_service(ch, var) {
	assert(var);
	var = false;
	ch!SUCCESS
}

/* inventory service */
proctype Inventory() {
    bool reserved = false;

    do
    :: inv_channel?EXECUTE ->
        if
        :: reserved = true;
           inv_channel!SUCCESS
        :: inv_channel!FAILURE
        fi;
        do
        :: inv_channel?ROLLBACK ->
            rollback_service(inv_channel, reserved);
        :: inv_channel?TERMINATE ->
            inv_channel!ACK;
            break
        od;
        break
    :: inv_channel?TERMINATE ->
        inv_channel!ACK;
        break
    od
}


/* payment service */
proctype Payment() {
    bool confirmed = false;
    do
    :: pay_channel?EXECUTE ->
        if
        :: confirmed = true;
           pay_channel!SUCCESS
        :: pay_channel!FAILURE
        fi;
        do
        :: pay_channel?ROLLBACK ->
            rollback_service(pay_channel, confirmed);
        :: pay_channel?TERMINATE ->
            pay_channel!ACK;
            break
        od;
        break
    :: pay_channel?TERMINATE ->
        pay_channel!ACK;
        break
    od
}

/* shipment service */
proctype Shipping() {
    bool prepared = false;
    do
    :: ship_channel?EXECUTE ->
        if
        :: prepared = true;
           ship_channel!SUCCESS
        :: ship_channel!FAILURE
        fi;
        do
        :: ship_channel?ROLLBACK ->
        	/* as there can't be any failures after shipment is successfully done, it couldn't expect a ROLLBACK message.
	   		   But the assignment description explicitly stated that it should support ROLLBACK messages */
            rollback_service(ship_channel, prepared);
        :: ship_channel?TERMINATE ->
            ship_channel!ACK;
            break
        od;
        break
    :: ship_channel?TERMINATE ->
        ship_channel!ACK;
        break
    od
}



/* Coordinator */
proctype Coordinator()
{
    mtype result;

    /* ask inventory to reserve the products */
    inv_channel!EXECUTE;
    inv_channel?result;

    if
    :: result == FAILURE -> 
        skip

    :: result == SUCCESS ->
        /* ask payment to authorize the payment */
        pay_channel!EXECUTE;
        pay_channel?result;

        if
        :: result == FAILURE ->
            /* payment failed: unreserve */
            compensate_service(inv_channel, result);

        :: result == SUCCESS ->
            /* ask shipping to ship */
            ship_channel!EXECUTE;
            ship_channel?result;

            if
            :: result == FAILURE ->
                /* shipping failed: undo payment, unreserve */
	            compensate_service(pay_channel, result);
                compensate_service(inv_channel, result);

            :: result == SUCCESS ->
                transaction_completed = true
            fi
        fi
    fi;

	/* temination */
    terminate_service(inv_channel);
	terminate_service(pay_channel);
	terminate_service(ship_channel);
}


init {
    run Inventory();
    run Payment();
    run Shipping();
    run Coordinator();
}