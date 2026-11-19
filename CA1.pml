mtype = {
    EXECUTE,
    ROLLBACK,
    TERMINATE,
    SUCCESS,
    FAILURE,
    ACK
};

/* channels: inventory - coordinator */
chan inv_request  = [0] of { mtype };
chan inv_response = [0] of { mtype };

/* channels: payment - coordinator */
chan pay_request  = [0] of { mtype };
chan pay_response = [0] of { mtype };

/* channels: shipping - coordinator */
chan ship_request  = [0] of { mtype };
chan ship_response = [0] of { mtype };

/* true only when inventory, payment, and shipping all succeed. */
bool transaction_completed = false;


/* inventory service */
proctype Inventory()
{
    bool reserved = false;

    inv_request?EXECUTE;

    if
    :: reserved = true;
       inv_response!SUCCESS
    :: inv_response!FAILURE
    fi;

    do
    :: inv_request?ROLLBACK ->
        assert(reserved);
        reserved = false;
        inv_response!SUCCESS

    :: inv_request?TERMINATE ->
        inv_response!ACK;
        break
    od
}


/* Coordinator */
proctype Coordinator()
{
    mtype result;

    /* ask inventory to reserve the products */
    inv_request!EXECUTE;
    inv_response?result;

    if
    :: result == FAILURE -> 
        skip

    :: result == SUCCESS ->
        /* ask payment to authorize the payment */
        pay_request!EXECUTE;
        pay_response?result;

        if
        :: result == FAILURE ->
            /* payment failed: unreserve */
            inv_request!ROLLBACK;
            inv_response?result;
            assert(result == SUCCESS)

        :: result == SUCCESS ->
            /* ask shipping to ship */
            ship_request!EXECUTE;
            ship_response?result;

            if
            :: result == FAILURE ->
                /* shipping failed: undo payment, unreserve */
                pay_request!ROLLBACK;
                pay_response?result;
                assert(result == SUCCESS);

                inv_request!ROLLBACK;
                inv_response?result;
                assert(result == SUCCESS)

            :: result == SUCCESS ->
                transaction_completed = true
            fi
        fi
    fi;

	/* temination */
    inv_request!TERMINATE;
	inv_response?ACK;
	
	pay_request!TERMINATE;
	pay_response?ACK;
	
	ship_request!TERMINATE;
	ship_response?ACK;
}